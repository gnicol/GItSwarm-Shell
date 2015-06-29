require_relative 'init'
require_relative '../lib/gitlab_config'

module PerforceSwarm
  class GitlabConfig < GitlabConfig
    def git_fusion
      @config['git_fusion'] ||= {}
    end
  end
end
