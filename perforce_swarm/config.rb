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
      return config['default'] || config.first[1] unless id

      # config block ID was specified, but not found - we should throw
      fail "Git Fusion config block #{id} requested, not not found." unless config[id]

      # return the config block
      config[id]
    end
  end
end
