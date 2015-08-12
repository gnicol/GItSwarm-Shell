require_relative '../lib/gitlab_init'

module PerforceSwarm
  class GitlabConfig < GitlabConfig
    def git_fusion
      @git_fusion ||= GitFusion::Config.new(@config['git_fusion'])
    end
  end

  module GitFusion
    class Config
      def initialize(config)
        @config = config.is_a?(Hash) ? config : {}
        @config['enabled'] ||= false
      end

      def [](key)
        @config[key]
      end

      def []=(key, value)
        @config[key] = value
      end

      def enabled?
        @config['enabled']
      end

      def entries
        entries = @config.select do |id, value|
          value.is_a?(Hash) && !value['url'].nil? && !value['url'].empty? && id != 'global'
        end

        fail 'No Git Fusion configuration found.' if entries.empty?
        entries.each do |id, value|
          value['id'] = id
          entries[id] = GitFusion::ConfigEntry.new(value, @config['global'])
        end
      end

      def entry(id = nil)
        entry_list = entries

        fail "Git Fusion config entry '#{id}' does not exist." if id && !@config[id]
        fail "Git Fusion config entry '#{id}' is malformed."   if id && !entry_list[id]

        # if no id was specified, use the first entry
        id ||= entry_list.first[0]
        entry_list[id]
      end
    end

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

      def perforce
        @entry['perforce'] || {}
      end

      def global_perforce
        global['perforce'] || {}
      end

      # returns the password (or empty string if not found) with the following priority:
      #  1) entry-specific password
      #  2) password specified in the entry-specific URL
      #  3) global password
      #  4) empty string
      def git_fusion_password
        @entry['password'] || url.password || global['password'] || ''
      end

      # returns the perforce password (or the empty string if not found) with the following priority:
      #  1) entry-specific perforce password
      #  2) entry-specific password
      #  3) password specified in the entry-specific URL
      #  4) global perforce password
      #  5) global password (gives empty string as global default if not specified)
      def perforce_password
        perforce['password'] || @entry['password'] || url.password || global_perforce['password'] || global['password']
      end

      # returns the perforce username (or 'gitswarm' if not found) with the following priority:
      #  1) entry-specific perforce user
      #  2) entry-specific user
      #  3) username specified in the entry-specific URL if it is HTTP/S
      #  4) global perforce user
      #  5) global user (gives 'gitswarm' as global default if not specified)
      def perforce_username
        url_user             = @entry['url'].scheme != 'scp' && @entry['url'].user
        perforce['user'] || @entry['user'] || url_user || global_perforce['user'] || global['user']
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
