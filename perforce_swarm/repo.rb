require_relative '../lib/gitlab_init'
require_relative 'utils'

module PerforceSwarm
  class Repo
    def initialize(repo_path)
      repo_path = File.realpath(repo_path)
      fail 'Not a valid repo path' unless File.exist?(File.join(repo_path, 'config'))
      @repo_path = repo_path
    end

    def mirrored?
      return false unless mirror_url
      true
    end

    def mirror_url=(url)
      # construct the Git Fusion URL based on the mirror URL given
      # run the git command to add the remote
      resolved_url = GitFusionRepo.resolve_url(url)
      Utils.popen(%w(git remote remove mirror), @repo_path)
      output, status = Utils.popen(['git', 'remote', 'add', 'mirror', resolved_url], @repo_path)
      @mirror_url    = nil
      unless status.zero? && mirror_url == resolved_url
        fail "Failed to add mirror remote #{url} to #{@repo_path} its still #{mirror_url}\n#{output}"
      end

      url
    end

    def mirror_url
      return @mirror_url if @mirror_url

      @mirror_url, status = Utils.popen(%w(git config --get remote.mirror.url), @repo_path)
      @mirror_url.strip!
      @mirror_url = false unless status.zero? && !@mirror_url.empty?
      @mirror_url
    end
  end
end
