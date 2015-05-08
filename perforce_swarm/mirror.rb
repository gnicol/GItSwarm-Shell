require 'open3'
require 'socket'
require 'tmpdir'
require_relative '../lib/gitlab_init'
require_relative '../lib/gitlab_post_receive'
require_relative '../lib/gitlab_custom_hook'

module PerforceSwarm
  class Mirror
    class Exception < StandardError
    end

    # System User Constant
    SYSTEM_USER = 'system-user'

    # Constant used in ENV[WRITE_LOCK_SOCKET] when there is no
    # socket due to the requested repo not being mirrored
    NOT_MIRRORED = '__NOT_MIRRORED__'

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
      cmd_output.gsub!(/\r\n|\r/, "\n")

      [cmd_output, cmd_status]
    end

    # if we have a 'mirror' remote, we push to it first and reject everything if its unhappy
    # note this will echo output from the mirror to stdout so the user can see it
    # @todo; from the docs tags may need a leading + to go through this way; test and confirm
    def self.push(refs, repo_path, options = {})
      mirror = mirror_url(repo_path)

      # Set default options and check that this function is being called correctly
      options = { receive_pack: false, require_block: !options[:receive_pack] }.merge(options)
      fail ArgumentError, 'By default a block is required' if options[:require_block] && !block_given?

      if options[:receive_pack]
        socket_path = ENV['WRITE_LOCK_SOCKET']
        fail Exception, 'WRITE_LOCK_SOCKET is required for :receive_pack' unless socket_path
        if mirror && !File.socket?(socket_path)
          fail Exception, "WRITE_LOCK_SOCKET is not a valid socket\n#{socket_path}"
        end
        if !mirror && !File.socket?(socket_path) && socket_path != NOT_MIRRORED
          fail Exception, "WRITE_LOCK_SOCKET is invalid\n#{socket_path}"
        end
      end

      # if we are mirroring; filter the involved refs if needed
      refs = mirror_push_refs(repo_path, refs) if mirror

      # no configured mirror or all refs filtered means nutin to do; exit happy!
      unless mirror && !refs.to_a.empty?
        yield(mirror) if block_given?
        return
      end

      # stores the time taken for various phases
      durations = Durations.new

      # Take out a write lock around the push to mirror
      # During a :receive_pack operation we cannot take out this lock ourselves as
      # we want it held through post-receive which is a different process, so
      # we communicate with our custom git-receive-pack script to do the locking
      durations.start(:lock)
      locked = write_lock(repo_path, options[:receive_pack])
      durations.stop(:lock)

      # push the ref updates to the remote mirror and fail out if they are unhappy
      durations.start(:push)
      push_output, status = popen(['git', 'push', 'mirror', '--', *refs], repo_path, true)
      durations.stop(:push)
      fail Exception, push_output unless status.zero?

      # try to extract the push id. if we don't have one we're done
      push_id = push_output[/^(?:remote: )?Commencing push (\d+) processing.../, 1]
      unless push_id
        yield(mirror) if block_given?
        return
      end

      # git-fusion returns from the push early, we want to delay till its all the way into p4d
      # we swap to a temp dir (to ensure we don't get errors for being already in a git repo)
      # and we clone the @wait@RepoName to delay till its done
      durations.start(:wait)
      wait_outputs = ''
      Dir.mktmpdir do |temp|
        # we wait until the push is complete. out of concern the http connection to the mirror may
        # time out we keep retrying the wait until we see success or that the operation is done
        wait = mirror.gsub(%r{/([^/]*/?$)}, '/@wait@\1@' + push_id)
        wait = mirror.gsub(%r{:([^:]*/?$)}, ':@wait@\1@' + push_id) if mirror == wait
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
          wait_outputs += output

          # if we have a success message we are on a newer git-fusion and don't need to hit @status
          if output =~ /^(?:remote: )?Push \d+ completed successfully/
            yield(mirror) if block_given?
            return nil  # the nil makes rubocop happy
          end

          # blow up if it looks like the attempt didn't at least try to wait
          fail Exception, output unless output =~ /Waiting for push \d+.../
        end
      end
      durations.stop(:wait)
    rescue StandardError => e
      $logger.error "Push to mirror failed for: #{repo_path}\n#{refs * "\n"}\n#{e.message}"

      # don't hold the lock while we communicate our displeasure over the network to the client
      begin
        write_unlock(repo_path, options[:receive_pack]) if locked && options[:receive_pack]
      rescue
        # this unlock is a courtesy, quash any exceptions
        nil # make rubocop happy
      end

      raise e
    ensure
      # For local locking, ensure we unlock before we exit this method
      write_unlock(repo_path) if locked && !options[:receive_pack]

      # We anticipate a whack of lines for each phase of the progress but we want to trim it to only list the last
      # last entry for each section. The general vibe of the output is:
      # Perforce:   5% ( 1/17) Loading commit tree into memory...
      # *cut for terseness*
      # Perforce: 100% (17/17) Loading commit tree into memory...
      # Perforce:   5% ( 1/18) Finding child commits...
      # *cut for terseness*
      #
      # The regex matches the leading portion and captures the section label e.g. 'Finding child commits...' as \1
      # It scans over more lines with that same title capturing the last one in \2 and setting that to be the block.
      push_output.gsub!(%r{Perforce: +\d+% +\( *\d+/\d+\) (.*?)\n([^\n]+\1\n)+}m, '\2') if push_output

      message = "Push: #{repo_path}\n"
      message += "#{refs * "\n"}\n" if $! # skips refs if an exception occured, they were already logged
      message += "Durations #{durations}\n#{push_output}#{wait_outputs}"
      $logger.info message
    end

    # perform safe fetch but then throws an exception if errors occurred
    def self.fetch!(repo_path, skip_if_pushing = false)
      fail Exception, last_fetch_error(repo_path) unless fetch(repo_path, skip_if_pushing)
    end

    # fetch from the remote mirror (if there is one) and return success/failure
    # @todo; when we fetch remove branches/tags/etc no longer present on the master remote mirror
    def self.fetch(repo_path, skip_if_pushing = true)
      # see if we have a mirror remote, if not nothing to do
      return true unless (mirror = mirror_url(repo_path))

      # the lock is automatically released after the blocks finish, but we manually release the lock for performance.
      File.open(File.join(repo_path, 'mirror_push.lock'), 'w+', 0644) do |push_handle|
        begin
          # we honor push locks to ensure we don't pull down partially mirror pushed changes causing ref locking errors.
          # for pure reads, instead of waiting we just skip the mirror pull if a push lock is in place
          return !last_fetch_error(repo_path) if skip_if_pushing && !push_handle.flock(File::LOCK_NB | File::LOCK_SH)

          # looks like we're not push locked or we're not skipping, ensure we have a shared push lock before continuing
          push_handle.flock(File::LOCK_SH)

          # we use a fetch lock to avoid a 'cache stampede' style issue should multiple pullers overlap
          File.open(File.join(repo_path, 'mirror_fetch.lock'), 'w+', 0644) do |fetch_handle|
            begin
              error_file = File.join(repo_path, 'mirror_fetch.error')
              # Try and take the lock, but don't yet block if it's already taken
              unless fetch_handle.flock(File::LOCK_NB | File::LOCK_EX)
                # Looks like someone else is already doing a pull
                # We will wait for them to finish and then use their result
                fetch_handle.flock(File::LOCK_SH)
                return !last_fetch_error(repo_path)
              end

              # Now that we are locked, grab our current refs
              old_refs = show_ref(repo_path)

              # fetch from the mirror, if that fails then capute failure details
              durations = Durations.new
              durations.start(:fetch)
              output, status = popen(%w(git fetch mirror) + mirror_fetch_refs(repo_path), repo_path)
              durations.stop
              File.write(File.join(repo_path, 'mirror_fetch.last'), Time.now.to_i)
              fail Exception, output unless status.zero?

              # Everything went well, clear the error file if present
              FileUtils.safe_unlink(error_file)

              # Determine our new refs
              changes = show_ref_updates(old_refs, show_ref(repo_path))

              # If we have changes, post them to redis
              if changes && !changes.strip.empty?
                # Make sure we don't pass along our fetch user to write actions
                user, ENV['GL_ID'] = ENV['GL_ID'], nil
                GitlabPostReceive.new(repo_path, SYSTEM_USER, changes).send(:update_redis)
                GitlabCustomHook.new.post_receive(changes, repo_path, receive_pack: false)
                ENV['GL_ID'] = user
              end

              return true
            rescue Mirror::Exception => e
              # Something went wrong, record the details
              $logger.error "Mirror fetch failed.\nRepo Path: #{repo_path}\nMirror: #{mirror}\n#{e.message}"
              File.write(error_file, e.message)
              return false
            ensure
              fetch_handle.flock(File::LOCK_UN)
              fetch_handle.close
              if durations && output
                message = "Mirror fetch\nRepo Path: #{repo_path}\nMirror: #{mirror}\nDuration #{durations}\n"
                message += "Exit Status: #{status}\n#{output}"
                $logger.info message
              end
            end
          end
        ensure
          push_handle.flock(File::LOCK_UN)
          push_handle.close
        end
      end
    end

    # returns the UNIX timestamp of the last fetched (success or failure) or false if there is
    # no mirror remote, or there was an error while fetching the timestamp
    def self.last_fetched(repo_path)
      # see if we have a mirror remote; if not, nothing to do
      return false unless mirror_url(repo_path)

      Time.at(File.read(File.join(repo_path, 'mirror_fetch.last')).strip.to_i)
    rescue
      return false
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

    def self.show_ref(repo_path)
      refs, status = popen(%w(git show-ref --heads --tags), repo_path)
      fail "git show-ref failed with:\n#{refs}" unless status.zero?
      refs.strip!
    end

    def self.show_ref_updates(old_refs, new_refs)
      old_refs, new_refs, changes = old_refs.split("\n"), new_refs.split("\n"), {}

      # Loop over anything that was modified or deleted, and create a changes entry for it
      # Initially we assume deletes occured, but we will touch them up to be edits later
      (old_refs - new_refs).each do |ref|
        fail "invalid ref output:\n#{ref}" unless ref =~ /^\h{40} \S+$/
        sha, refspec = ref.strip.split(' ')
        changes[refspec] = [sha, '0' * 40, refspec]
      end

      # Loop over anything that was modified or added, and create/update changes entry for it
      (new_refs - old_refs).each do |ref|
        fail "invalid ref output:\n#{ref}" unless ref =~ /^\h{40} \S+$/
        sha, refspec = ref.strip.split(' ')
        # If refspec doesn't exist yet, this will be an add
        changes[refspec]  ||= ['0' * 40, sha, refspec]
        # Ensure any 'false deletes' are touched up to be edits
        changes[refspec][1] = sha
      end

      changes.map { |_refspec, refs|  refs.join(' ') }.join("\n")
    end

    def self.write_lock(repo_path, use_socket = false)
      return lock_socket('LOCK') if use_socket

      $logger.debug "Write Locking repo: #{repo_path}"

      lock_file = File.join(File.realpath(repo_path), 'mirror_push.lock')
      @push_locks ||= {}
      @push_locks[lock_file] ||= File.open(lock_file, 'w+', 0644)
      @push_locks[lock_file].flock(File::LOCK_EX)
      @push_locks[lock_file]
    end

    def self.write_unlock(repo_path, use_socket = false)
      return lock_socket('UNLOCK') if use_socket

      begin
        @push_locks ||= {}
        lock_file = File.join(File.realpath(repo_path), 'mirror_push.lock')
        if @push_locks[lock_file]
          $logger.debug "Write Unlocking repo: #{repo_path}"
          @push_locks[lock_file].flock(File::LOCK_UN)
          @push_locks.delete(lock_file)
        else
          $logger.debug "Attempted to Write Unlock already unlocked repo: #{repo_path}"
        end
        true
      rescue
        return false
      end
    end

    # used to send the command LOCK or UNLOCK to the write lock socket
    # only usable on mirrored repos during a push operation via receive_pack
    def self.lock_socket(command)
      socket = UNIXSocket.new(ENV['WRITE_LOCK_SOCKET'])
      socket.puts command.strip
      socket.flush
      response = socket.gets.to_s.strip
      socket.close
      if response != "#{command}ED"
        fail Exception, "Expected #{command}ED confirmation but received: #{response}"
      end
      response
    end

    def self.mirror_push_refs(repo_path, refs)
      # filter the passed refs to only included items matching at least one of the active ref patterns
      active = File.readlines(File.join(repo_path, 'mirror_refs.active')).map(&:strip)
      refs.select! do |ref|
        active.find_index { |pattern| File.fnmatch(pattern, ref[%r{.*:(refs/[^/]+/.+$)}, 1] || '') }
      end
      refs.compact
    rescue
      return refs
    end

    def self.mirror_fetch_refs(repo_path)
      File.readlines(File.join(repo_path, 'mirror_refs.active')).map do |ref|
        "#{ref.strip}:#{ref.strip}"
      end
    rescue
      return ['refs/*:refs/*']
    end
  end

  class Durations
    def initialize
      @durations = {}
    end

    def start(id)
      fail 'Cannot start timer, id has already been used' if @durations[id]
      @durations[id] = { start: Time.now.to_f, stop: nil }
    end

    def stop(id = nil)
      id = @durations.keys.last unless id
      fail 'There are no active timers' if @durations.empty?
      fail 'No active timer under specified id' unless @durations[id]
      fail 'Timer is already stopped' if @durations[id][:stop]
      @durations[id][:stop] = Time.now.to_f
    end

    def to_s
      now = Time.now.to_f
      @durations.map { |id, timer| "#{id}: #{format('%.3f', (timer[:stop] || now) - timer[:start])}" }.join(' ')
    end
  end
end
