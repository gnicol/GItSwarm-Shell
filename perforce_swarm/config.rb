require_relative 'init'
require_relative '../lib/gitlab_config'

module PerforceSwarm
  class GitlabConfig < GitlabConfig
    def git_fusion
      @config['git_fusion'] ||= {}
    end

    def git_fusion_config_block(id = nil)
      config = git_fusion

      fail 'No Git Fusion configuration found.' if config.nil? || config.empty?

      # use the 'default' block if one is found - otherwise just use the first one
      return config['default'] || config.first[1] if id.nil?

      # look for a block with the given ID, and return it if found
      return config[id] if config[id]

      # config block ID was specified, but not found - we should throw
      fail "Git Fusion config block #{id} requested, not not found."
    end
  end
end
