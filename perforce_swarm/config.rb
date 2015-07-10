require_relative 'init'
require_relative '../lib/gitlab_config'

module PerforceSwarm
  class GitlabConfig < GitlabConfig
    def git_fusion
      @config['git_fusion'] = {} unless @config['git_fusion'].is_a?(Hash)
      @config['git_fusion']['enabled'] ||= false
      @config['git_fusion']
    end

    def git_fusion_enabled?
      git_fusion['enabled']
    end

    def git_fusion_entry(id = nil)
      config = git_fusion

      # remove any keys that are not hashes or don't have a URL defined
      stripped = config
      stripped.delete_if { |_key, value| !value.is_a?(Hash) || value['url'].nil? }

      fail 'No Git Fusion configuration found.'               if stripped.nil? || stripped.empty?
      fail "Git Fusion config entry '#{id}' does not exist."  if id && !stripped[id]
      fail "Git Fusion config entry '#{id}' is malformed."    if id && config[id] && !stripped[id]

      # if no id was specified, use 'default' if that key exists
      # otherwise, just use the first entry
      id ||= 'default' if stripped['default']
      id ||= stripped.first[0]

      # pull out the selected entry and ensure it has its id on it
      entry       = stripped[id]
      entry['id'] = id
      entry
    end
  end
end
