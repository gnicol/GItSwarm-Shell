require 'open3'
require 'tmpdir'
require_relative '../lib/gitlab_init'

# @todo; for push and fetch perhaps flush? the output is just coming in one whallop as it is
# @todo; if we could detect that a pull hadn't run recently we could trigger one in push to protect against missed spots
module PerforceSwarm
  class Mirror
    class Exception < ::Exception
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
        # this is somewhat laborious as git-fusion returns line endings of both 0x0a and 0x0d :(
        line = ''
        stdout_and_stderr.each_char do |char|
          cmd_output << char

          # if this is just part of an \r\n sequence remember it and continue
          next if char == "\n" && cmd_output[-2] == "\r"

          # if we're not on a newline character just capture into line and continue
          if char != "\n" && char != "\r"
            line << char
            next
          end

          # strip the remote lead-in and print/yield as needed if the line has content
          line.gsub!(/^remote: /, '')
          puts line  if !line.empty? && stream_output
          yield line if !line.empty? && block_given?
          line = ''
        end

        # if there was data left in line print/yield as needed if the line has content
        line.gsub!(/^remote: /, '')
        puts line  if !line.empty? && stream_output
        yield line if !line.empty? && block_given?

        cmd_status = wait_thr.value.exitstatus
      end

      [cmd_output, cmd_status]
    end

    # push to the remote mirror (if there is one)
    # note this will echo output from the mirror to stdout so the user can see it
    # @todo; from the docs tags may need a leading + to go through this way; test and confirm
    def self.push(refs, repo_path)
      # if we have a 'mirror' remote, we push to it first and reject everything if its unhappy

      # no configured mirror means nutin to do; exit happy!
      mirror, status = popen(%w(git config --get remote.mirror.url), repo_path)
      mirror.strip!
      return unless status.zero? && !mirror.empty?

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
            puts line unless line =~ /^Cloning into/ || silenced
          end

          # if we have a success message we are on a newer git-fusion and don't need to hit @status
          return if output =~ /^(?:remote: )?Push \d+ completed successfully/

          # blow up if it looks like the attempt didn't at least try to wait
          fail Exception, output unless output =~ /Waiting for push \d+.../
        end
      end
    rescue PerforceSwarm::Mirror::Exception => e
      $logger.error "Push to mirror failed for: #{repo_path}\n#{refs * "\n"}\n#{e.message}"
      raise e
    end

    # fetch from the remote mirror (if there is one)
    # @todo; when we fetch remove branches/tags/etc no longer present on the master remote mirror
    def self.fetch(repo_path)
      # see if we have a mirror remote, if not nothing to do
      mirror, status = popen(%w(git config --get remote.mirror.url), repo_path)
      mirror.strip!
      return unless status.zero? && !mirror.empty?

      # fetch from the mirror, if that fails return the details
      output, status = popen(%w(git fetch mirror refs/*:refs/*), repo_path)
      unless status.zero?
        $logger.error "Fetch from mirror failed for: #{repo_path}\n#{output}"
        fail Exception, output
      end

      # @todo; if we know the user is pulling and the mirror is busy; skip the pull to avoid GF read lock?
      # @todo; add some fs level locking so this pull can't update refs before a mirror push wraps up
    end
  end
end
