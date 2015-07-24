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

    def global_entry
      global  = git_fusion['global'] || {}

      # ensure defaults are set correctly, and url is removed from the global config
      global['user']     ||= 'gitswarm'
      global['password'] ||= ''
      global['url']        = nil
      global
    end

    def git_fusion_entry(id = nil)
      entries = valid_entries

      fail 'No Git Fusion configuration found.'               if entries.nil? || entries.empty?
      fail "Git Fusion config entry '#{id}' does not exist."  if id && !entries[id]
      fail "Git Fusion config entry '#{id}' is malformed."    if id && git_fusion[id] && !entries[id]

      # if no id was specified, use the first entry
      id ||= entries.first[0]

      # create the requested entry
      ConfigEntry.new(entries[id], global_entry)
    end

    def valid_entries
      # remove any keys that are not hashes, don't have a URL defined or are our 'global' block
      entries = git_fusion.clone
      entries.delete_if do |key, value|
        !value.is_a?(Hash) || value['url'].nil? || value['url'].empty? || key == 'global'
      end

      # add an 'id' field to each key
      entries.each_key { |id| entries[id]['id'] = id }
    end
  end

  class ConfigEntry
    attr_reader :entry, :global
    def initialize(entry, global = {})
      @entry  = entry
      @global = global
    end

    def [](key)
      return entry[key]  if entry[key]
      return global[key] if global[key]
      nil
    end

    def []=(key, value)
      entry[key] = value
    end
  end
end
