require_relative 'init'
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
      fail 'Mirror URL must start with mirror://' unless url.start_with?('mirror://')
      parsed = url.sub(%r{^mirror://}, '').split('/')
      fail "Invalid Mirror URL provided: #{url}" unless parsed.length == 2

      config = PerforceSwarm::GitlabConfig.new.git_fusion_entry(parsed[0])
      url    = PerforceSwarm::GitFusion::URL.new(config['url']).repo(parsed[1])

      # run the git command to add the remote
      output = ''
      Utils.popen(['git', *GitFusion.git_config_params(config['id'], config['git_config_params']),
                   'remote', 'add', 'mirror', url.to_s], local_path) do |line|
        # TODO: check for success/failure
        output += line
      end
      # TODO: return a useful value around success/failure here
      output.chomp
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
