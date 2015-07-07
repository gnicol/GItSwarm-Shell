require_relative 'init'
require_relative '../lib/gitlab_config'

module PerforceSwarm
  class GitlabConfig < GitlabConfig
    def git_fusion
      @config['git_fusion'] ||= {}
    end

    def git_fusion_entry(id = nil)
      config = git_fusion

      fail 'No Git Fusion configuration found.' if config.nil? || config.empty?
      fail "Git Fusion config block '#{id}' requested, but not found." if id && !config[id]

      # if no id was specified, use 'default' if that key exists
      # otherwise, just use the first entry
      id ||= 'default' if config['default']
      id ||= config.first[0]

      # pull out the selected entry and ensure it has its id on it
      block = config[id]
      block['id'] = id

      fail "No URL specified in Git Fusion config block '#{id}': " + block.inspect unless block && block['url']
      block
    end
  end
end
