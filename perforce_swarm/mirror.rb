require 'open3'
require 'socket'
require 'tmpdir'
require_relative '../lib/gitlab_init'

# @todo; for push and fetch perhaps flush? the output is just coming in one whallop as it is
# @todo; if we could detect that a pull hadn't run recently we could trigger one in push to protect against missed spots
module PerforceSwarm
  class Mirror
    class Exception < StandardError
    end

    def self.popen(cmd, path = nil, stream_output = nil)
      unless cmd.is_a?(Array)
        fail 'System commands must be given as an array of strings'
      end

      path  ||= Dir.pwd
      vars    = { 'PWD' => path }
      options = { chdir: path }

      FileUtils.mkdir_p(path) unless File.directory?(path)

      cmd_output = ''
      cmd_status = 0
      Open3.popen2e(vars, *cmd, options) do |stdin, stdout_and_stderr, wait_thr|
        # some apps won't fully start till stdin is closed up; we don't use it so close it
        stdin.close

        # read a line at a time from stdout/stderr and capture/report it as needed
        # be aware git-fusion uses 0x0D, \r to stack progress output and 0x0A, \n to really line break between hunks.
        line = ''
        stdout_and_stderr.each_char do |char|
          cmd_output << char
          line       << char

          # if we're not on a newline character just capture into line and continue
          # note this means the \n in a \r\n sequence gets processed as its own line
          # we do not however normally expect to encounter \r\n sequences.
          next unless char == "\n" || char == "\r"

          # strip the remote lead-in and print/yield as needed if the line has content
          line.gsub!(/^remote: /, '')
          print line if !line.empty? && stream_output
          yield line if !line.empty? && block_given?
          line = ''
        end

        # if there was data left in line print/yield as needed if the line has content
        line.gsub!(/^remote: /, '')
        print line if !line.empty? && stream_output
        yield line if !line.empty? && block_given?

        cmd_status = wait_thr.value.exitstatus
      end

      # for the non-streamed output, normalize line-endings to \n
      # this makes it much easier to play with them using regex or to log them
      cmd_output.gsub!(/\r\n\|\r/, "\n")

      [cmd_output, cmd_status]
    end

    # push to the remote mirror (if there is one)
    # note this will echo output from the mirror to stdout so the user can see it
    # @todo; from the docs tags may need a leading + to go through this way; test and confirm
    # @todo; when we have push and pull locks, our call to pull will have to specify an ignore push lock
    def self.push(refs, repo_path)
      # if we have a 'mirror' remote, we push to it first and reject everything if its unhappy

      # no configured mirror means nutin to do; exit happy!
      return unless (mirror = mirror_url(repo_path))

      # we communicate with our custom git-receive-pack script to take out a write lock around the mirror operation
      # we cannot take out this lock ourselves as we want it held through post-receive which is a different process
      fail Exception 'Expected WRITE_LOCK_SOCKET to be set in environment' unless ENV['WRITE_LOCK_SOCKET']
      socket = UNIXSocket.new(ENV['WRITE_LOCK_SOCKET'])
      socket.puts 'LOCK'
      socket.flush
      fail Exception 'Expected LOCKED confirmation' unless socket.gets.chomp == 'LOCKED'
      socket.close

      # push the ref updates to the remote mirror and fail out if they are unhappy
      push_output, status = popen(['git', 'push', 'mirror', '--', *refs], repo_path, true)
      fail Exception, push_output unless status.zero?

      # try to extract the push id. if we don't have one we're done
      push_id = push_output[/^(?:remote: )?Commencing push (\d+) processing.../, 1]
      return unless push_id

      # git-fusion returns from the push early, we want to delay till its all the way into p4d
      # we swap to a temp dir (to ensure we don't get errors for being already in a git repo)
      # and we clone the @wait@RepoName to delay till its done
      Dir.mktmpdir do |temp|
        # we wait until the push is complete. out of concern the http connection to the mirror may
        # time out we keep retrying the wait until we see success or that the operation is done
        wait = mirror.gsub(%r{/([^/]*/?$)}, '/@wait@\1@' + push_id)
        wait = mirror.gsub(/:([^:]*\/?$)/, ':@wait@\1@' + push_id) if mirror == wait
        if mirror == wait
          puts message = "Unable to add @wait@ to mirror url: #{mirror}"
          fail Exception, message
        end

        loop do
          # do the wait and echo any output not related to the start/end of the clone attempt
          silenced  = false
          output, _ = popen(['git', 'clone', '--', wait], temp) do |line|
            silenced ||= line =~ /^fatal: /
            print line unless line =~ /^Cloning into/ || silenced
          end

          # if we have a success message we are on a newer git-fusion and don't need to hit @status
          return if output =~ /^(?:remote: )?Push \d+ completed successfully/

          # blow up if it looks like the attempt didn't at least try to wait
          fail Exception, output unless output =~ /Waiting for push \d+.../
        end
      end
    rescue Mirror::Exception => e
      $logger.error "Push to mirror failed for: #{repo_path}\n#{refs * "\n"}\n#{e.message}"
      raise e
    end

    # perform safe fetch but then throws an execption if errors occured
    def self.fetch!(repo_path)
      fail Exception, last_fetch_error(repo_path) unless fetch(repo_path)
    end

    # fetch from the remote mirror (if there is one) and return success/failure
    # @todo; when we fetch remove branches/tags/etc no longer present on the master remote mirror
    # @todo; if we know the user is pulling and the mirror is busy; skip the pull to avoid GF read lock?
    # @todo; add some fs level locking so this pull can't update refs before a mirror push wraps up
    def self.fetch(repo_path)
      # see if we have a mirror remote, if not nothing to do
      return true unless (mirror = mirror_url(repo_path))

      # Lock during mirror fetch. Lock is automatically released after this
      # block is finished, but we manually release the lock for performance.
      File.open(File.join(repo_path, 'mirror_fetch.lock'), 'w+', 0644) do |lock_handle|
        begin
          # Try and take the lock, but don't yet block if it's already taken
          unless lock_handle.flock(File::LOCK_NB | File::LOCK_EX)
            # Looks like someone else is already doing a pull
            # We will wait for them to finish and then use their result
            lock_handle.flock(File::LOCK_SH)
            return !last_fetch_error(repo_path)
          end

          # fetch from the mirror, if that fails then capute failure details
          output, status = popen(%w(git fetch mirror refs/*:refs/*), repo_path)
          error_file     = File.join(repo_path, 'mirror_fetch.error')
          if status.zero?
            # Everything went well, clear the error file if present
            FileUtils.safe_unlink(error_file)
            return true
          else
            # Something went wrong, record the details
            $logger.error "Mirror fetch failed.\nRepo Path: #{repo_path}\nMirror: #{mirror}\n#{output}"
            File.write(error_file, output)
            return false
          end
        ensure
          lock_handle.flock(File::LOCK_UN)
          lock_handle.close
        end
      end
    end

    def self.last_fetch_error(repo_path)
      # see if we have a mirror remote, if not nothing to do
      return false unless (mirror = mirror_url(repo_path))

      error = File.read(File.join(repo_path, 'mirror_fetch.error'))
      "Fetch from mirror: #{mirror} failed.\nPlease notify your Administrator.\n#{error}"
    rescue SystemCallError
      return false
    end

    def self.mirror_url(repo_path)
      mirror, status = popen(%w(git config --get remote.mirror.url), repo_path)
      mirror.strip!
      return false unless status.zero? && !mirror.empty?
      mirror
    end
  end
end
