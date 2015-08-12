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
      entries.each do |id, value|
        value['id'] = id
        entries[id] = GitFusion::ConfigEntry.new(value, git_fusion['global'])
      end
    end

    def git_fusion_entry(id = nil)
      entries = git_fusion_entries

      fail "Git Fusion config entry '#{id}' does not exist." if id && !git_fusion[id]
      fail "Git Fusion config entry '#{id}' is malformed."   if id && !entries[id]

      # if no id was specified, use the first entry
      id ||= entries.first[0]
      entries[id]
    end
  end

  module GitFusion
    class ConfigEntry
      def initialize(entry, global = {})
        @entry  = entry
        @global = global
      end

      def global
        # ensure defaults are set correctly, and url/label are removed from the global config
        global_config               = @global.is_a?(Hash) ? @global.clone : {}
        global_config['user']     ||= 'gitswarm'
        global_config['password'] ||= ''
        global_config.delete('url')
        global_config.delete('label')
        global_config
      end

      # returns the password (or empty string if not found) with the following priority:
      #  1) entry-specific password
      #  2) password specified in the entry-specific URL
      #  3) global password
      #  4) empty string
      def git_fusion_password
        @entry['password'] || url.password || global['password'] || ''
      end

      def url
        PerforceSwarm::GitFusion::URL.new(@entry['url'])
      end

      def [](key)
        key = 'git_fusion_password' if key == 'password'

        return send(key)   if respond_to?(key)
        return @entry[key] if @entry[key]
        global[key]
      end

      def []=(key, value)
        @entry[key] = value
      end
    end
  end
end
