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
      entries = git_fusion.select do |id, value|
        value.is_a?(Hash) && !value['url'].nil? && !value['url'].empty? && id != 'global'
      end

      fail 'No Git Fusion configuration found.' if entries.empty?
      global = global_entry
      entries.each do |id, value|
        value['id'] = id
        entries[id] = GitFusion::ConfigEntry.new(value, global)
      end
    end

    def global_entry
      global  = git_fusion['global'] || {}

      # ensure defaults are set correctly, and url/label are removed from the global config
      global['user']     ||= 'gitswarm'
      global['password'] ||= ''
      global.delete('url')
      global.delete('label')
      global
    end

    def git_fusion_entry(id = nil)
      entries = git_fusion_entries

      fail "Git Fusion config entry '#{id}' does not exist."  if id && !git_fusion[id]
      fail "Git Fusion config entry '#{id}' is malformed."    if id && !entries[id]

      # if no id was specified, use the first entry
      id ||= entries.first[0]

      # create the requested entry
      GitFusion::ConfigEntry.new(entries[id], global_entry)
    end
  end

  module GitFusion
    class ConfigEntry
      def initialize(entry, global = {})
        @entry  = entry
        @global = global
      end

      # returns the password (or empty string if not found) with the following priority:
      #  1) entry-specific password
      #  2) password specified in the entry-specific URL
      #  3) global password
      def git_fusion_password
        return @entry['password'] if @entry['password']

        url_password = PerforceSwarm::GitFusion::URL.new(@entry['url']).password
        return url_password if url_password

        @global['password'] || ''
      end

      def [](key)
        # if we're specifically looking for 'password' or 'git_fusion_password', we handle it differently
        return git_fusion_password if key == 'password' || key == 'git_fusion_password'
        return @entry[key]  if @entry[key]
        return @global[key] if @global[key]
        nil
      end

      def []=(key, value)
        @entry[key] = value
      end
    end
  end
end
