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
      fail "Git Fusion config block '#{id}' requested, but not found." if id && !config[id]

      if id
        block = config[id]
      else
        if config['default']
          id    = 'default'
          block = config['default']
        else
          first_block = config.first
          id          = first_block[0]
          block       = first_block[1]
        end
      end

      fail "No URL specified in Git Fusion config block '#{id}': " + block.inspect unless block && block['url']
      block['id'] = id
      block
    end
  end
end
