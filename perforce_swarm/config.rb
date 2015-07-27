require_relative '../lib/gitlab_init'

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

    def git_fusion_entries
      entries = git_fusion.select do |_id, value|
        value.is_a?(Hash) && !value['url'].nil? && !value['url'].empty?
      end
      entries.each do |id, _value|
        entries[id]['id'] = id
      end

      fail 'No Git Fusion configuration found.' if entries.empty?

      entries
    end

    def git_fusion_entry(id = nil)
      entries = git_fusion_entries

      # normalize default to nil so we'll pick the first entry if no 'default' key is present
      id = nil if id == 'default'

      fail "Git Fusion config entry '#{id}' does not exist."  if id && !git_fusion[id]
      fail "Git Fusion config entry '#{id}' is malformed."    if id && !entries[id]

      # if no id was specified, use 'default' if that key exists
      # otherwise, just use the first entry
      id ||= 'default' if entries['default']
      id ||= entries.first[0]

      entries[id]
    end
  end
end
