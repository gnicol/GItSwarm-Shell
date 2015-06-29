require_relative '../lib/gitlab_config'

module PerforceSwarm
  module GitFusion
    module GitlabConfigExtension
      def git_fusion
        @config['git_fusion'] ||= {}
      end
    end
  end
end

class GitlabConfig
  prepend PerforceSwarm::GitFusion::GitlabConfigExtension
end
