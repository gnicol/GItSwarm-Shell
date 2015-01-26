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
        until (line = stdout_and_stderr.gets).nil?
          cmd_output << line

          line.gsub!(/remote: /, '')
          puts line  if stream_output
          yield line if block_given?
        end

        cmd_status = wait_thr.value.exitstatus
      end

      [cmd_output, cmd_status]
    end

    # push to the remote mirror (if there is one)
    # note this will echo output from the mirror to stdout so the user can see it
    def self.push(refs, repo_path)
      # if we have a 'mirror' remote, we push to it first and reject everything if its unhappy

      # no configured mirror means nutin to do; exit happy!
      mirror, status = popen(%w(git config --get remote.mirror.url), repo_path)
      mirror.strip!
      return true unless status.zero? && !mirror.empty?

      # we have a mirror; figure out the updated refs so we can trial push to the mirror
      # @todo; from the docs tags may need a leading + to go through this way; test and confirm
      push_refs = []
      refs.split("\n").each do |refline|
        _src, tgt, ref = refline.strip.split
        refspec = (tgt.match(/^0+$/) ? '' : tgt) + ':' + ref
        push_refs.push(refspec)
      end

      # push the ref updates to the remote mirror and fail out if they are unhappy
      push_output, status = popen(['git', 'push', 'mirror', '--', *push_refs], repo_path, true)
      return false unless status.zero?

      # try to extract the push id. if we don't have one we're done
      push_id = push_output[/^remote: Commencing push (\d+) processing.../, 1]
      return true  unless push_id

      # git-fusion returns from the push early, we want to delay till its all the way into p4d
      # we swap to a temp dir (to ensure we don't get errors for being already in a git repo)
      # and we clone the @wait@RepoName to delay till its done
      require 'tmpdir'
      Dir.mktmpdir do |temp|
        wait = mirror.gsub(%r{/([^/]*/?$)}, '/@wait@\1')
        popen(['git', 'clone', '--', wait], temp) do |line|
          puts line unless line =~ /^Cloning into/ || line =~ /^fatal: repository .* not found$/
        end

        # @todo; we need to include the push id @wait@REPO@123 so we only wait for the correct push
        # @todo; the push may fail going into perforce; we need to scrape success/failure from the result message
        # @todo; we may not be talking to git-fusion; if there is really a repo called @wait@Foo can we avoid cloning?
        # @todo; the wait may time out and require retries, we should deal with that
      end

      true
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
      fail PerforceSwarm::Mirror::Exception, output unless status.zero?
    end
  end
end
