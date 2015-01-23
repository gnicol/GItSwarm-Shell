# @todo; we need to swap to something like popen3 to gracefully get the command output
# @todo; we need to strip the leading 'remote: ' from the mirror output as it doubles up
module PerforceSwarm
  class Mirror
    # push to the remote mirror (if there is one)
    # note this will echo output from the mirror to stdout so the user can see it
    def self.push(refs, repo_path)
      mirror = ''   # we want this method scope (not block scope) for re-use

      # if we have a 'mirror' remote, push to it first and reject everything if its unhappy
      Dir.chdir(repo_path) do
        # no configured mirror means nutin to do; exit happy!
        # we use $? not $CHILD_STATUS as the latter is nil erroneously on some ruby versions
        mirror = `git config --get remote.mirror.url`.strip
        return true unless $?.success? && !mirror.empty?  # rubocop:disable Style/SpecialGlobalVars

        # we have a mirror; figure out the updated refs so we can trial push to the mirror
        push_refs = []
        refs.split("\n").each do |refline|
          _src, tgt, ref = refline.strip.split
          push_refs.push(tgt + ':' + ref)
        end

        # push the ref updates to the remote mirror and fail out if they are unhappy
        return false unless system('git', 'push', 'mirror', '--', *push_refs)

        # @todo; from the docs tags may need a leading + to go through this way; test and confirm
      end

      # git-fusion returns from the push early, we want to delay till its all the way into p4d
      # we swap to a temp dir (to ensure we don't get errors for being already in a git repo)
      # and we clone the @wait@RepoName to delay till its done
      require 'tmpdir'
      Dir.mktmpdir do |temp|
        Dir.chdir(temp) do
          wait = mirror.gsub(%r{/([^/]*/?$)}, '/@wait@\1')
          system('git', 'clone', '--', wait)

          # @todo; we need to include the push id @wait@REPO@123 so we only wait for the correct push
          # @todo; the push may fail going into perforce; we need to scrape success/failure from the result message
          # @todo; we may not be talking to git-fusion; if there is really a repo called @wait@Foo can we avoid cloning?
          # @todo; the wait may time out and require retries, we should deal with that
        end
      end

      true
    end
  end
end
