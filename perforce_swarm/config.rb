require_relative '../lib/gitlab_config'

module PerforceSwarm
  module GitFusion
    module GitlabConfigExtension
      def fusion_url
        @config['fusion_url'] ||= nil
      end
    end
  end
end

class GitlabConfig
  prepend PerforceSwarm::GitFusion::GitlabConfigExtension
end
