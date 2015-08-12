require_relative 'init'
require_relative 'git_fusion'
require_relative 'utils'

module PerforceSwarm
  class GitFusionRepo
    # returns a hash mapping repo name to description for all repos for the given Git Fusion config entry
    def self.list(id = nil)
      parse_repos(PerforceSwarm::GitFusion.run(id, 'list'))
    rescue PerforceSwarm::GitFusion::RunError
      {}
    end

    # largely a separate method for testability
    def self.parse_repos(git_output)
      repos = {}
      return repos unless git_output

      # iterate over each repo found and build a hash mapping repo name to description
      # !%40%23   push utf8       A Git Fusion repo config ...
      # Talkhouse pull utf8       A description for this repo
      git_output.lines.each do |repo|
        if /^(?<name>[^\s]+)\s+(push|pull)?\s+([^\s]+)(\s+(?<description>.+?))?$/ =~ repo
          repos[name] = description.strip
        end
      end
      repos
    end

    # this method will resolve a mirror://instance-id/repo-id style url into the actual url
    # if a non-mirror:// url is passed in its just returned unmodified
    def self.resolve_url(mirror_url)
      # if its not 'mirror://' format no resolve is needed
      return mirror_url unless mirror_url && mirror_url.start_with?('mirror://')

      parsed = mirror_url.sub(%r{^mirror://}, '').split('/', 2)
      fail "Invalid Mirror URL provided: #{mirror_url}" unless parsed.length == 2

      config = PerforceSwarm::GitlabConfig.new.git_fusion.entry(parsed[0])
      PerforceSwarm::GitFusion::URL.new(config['url']).repo(parsed[1]).to_s
    end
  end
end
