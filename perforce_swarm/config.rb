require_relative '../lib/gitlab_init'

module PerforceSwarm
  class GitlabConfig < GitlabConfig
    def git_fusion
      @git_fusion ||= GitFusion::Config.new(@config['git_fusion'])
    end
  end

  module GitFusion
    class Config
      DEFAULT_USER            = 'gitswarm'
      DEFAULT_PASSWORD        = ''
      DEFAULT_MAX_FETCH_SLOTS = 2
      DEFAULT_MIN_OUTDATED    = 300

      def initialize(config)
        @config = config.is_a?(Hash) ? config : {}
        @config['enabled']        ||= false
        @config['fetch_worker']     = {} unless @config['fetch_worker'].is_a?(Hash)
        @config['fetch_worker'].merge!(
            'max_fetch_slots' => DEFAULT_MAX_FETCH_SLOTS,
            'min_outdated'    => DEFAULT_MIN_OUTDATED
        )
        @config
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

      def fetch_worker
        @config['fetch_worker']
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

      # returns the auto provisioned entry if found, otherwise raises an exception
      def auto_provisioned_entry
        entries.each do |_id, entry|
          return entry if entry['auto_provision']
        end
        fail 'Auto provision entry not found.'
      end

      def entry_by_url(url)
        url = PerforceSwarm::GitFusion::URL.new(url) unless url.is_a?(PerforceSwarm::GitFusion::URL)
        url = url.clear_path
        entries.each do |_id, entry|
          return entry if url == entry['url']
        end
        fail "Couldn't find a Git Fusion config entry for URL #{url}."
      end

      def entry(id = nil)
        entry_list = entries

        fail "Git Fusion config entry '#{id}' does not exist." if id && !@config[id]
        fail "Git Fusion config entry '#{id}' is malformed."   if id && !entry_list[id]

        # if no id was specified, use the first entry
        id ||= entry_list.first[0]
        entry_list[id]
      end

      def validate_entries(min_version = nil)
        fail "Invalid min_version specified: #{min_version}"  if min_version && !Gem::Version.correct?(min_version)
        min_version = Gem::Version.new(min_version)           if min_version

        # For every valid Git Fusion instance configuration attempt connection
        # and save appropriate result into an array for further processing
        results = {}
        entries.each do |id, config|
          begin
            # prime valid to false; should something go awry it stays there
            results[id]            = { valid: false, config: config, id: id }
            # verify we can run info and then parse out the version details
            results[id][:info]    = PerforceSwarm::GitFusion.run(id, 'info')
            # Version info: Rev. Git Fusion/2015.2/1128995 (2015/06/23).
            # Support version patches by converting to 2015.2.1128995
            info_version = results[id][:info].match(%r{^Rev\. Git Fusion/(\d{4}\.[^/]+)/(\d+)})
            results[id][:version] = "#{info_version[1]}.#{info_version[2]}"
            results[id][:valid]   = true

            # if we were given a min_version and could pull a git-fusion info version, enforce it
            version = Gem::Version.new(results[id][:version]) if Gem::Version.correct?(results[id][:version])
            if min_version && version && version < min_version
              results[id][:outdated] = true
              results[id][:valid]    = false
            end
          rescue RunError => ex
            results[id][:valid] = false
            results[id][:error] = ex.message
          end

          yield results[id] if block_given?
        end
        results
      end
    end

    class ConfigEntry
      def initialize(entry, global = {})
        @entry  = entry
        @global = global

        # normalize the 'perforce' and 'auto_create' entries to an empty hash
        @entry['perforce']    = {} unless @entry['perforce'].is_a?(Hash)
        @entry['auto_create'] = {} unless @entry['auto_create'].is_a?(Hash)
      end

      def global
        # ensure defaults are set correctly, and url/label are removed from the global config
        global_config                = @global.is_a?(Hash) ? @global.clone : {}
        global_config['user']      ||= DEFAULT_USER
        global_config['password']  ||= DEFAULT_PASSWORD
        global_config['perforce']    = {} unless global_config['perforce'].is_a?(Hash)
        global_config['auto_create'] = {} unless global_config['auto_create'].is_a?(Hash)
        global_config.delete('url')
        global_config.delete('label')
        global_config['perforce'].delete('port')
        global_config
      end

      # returns the password (or empty string if not found) with the following priority:
      #  1) entry-specific password
      #  2) password specified in the entry-specific URL
      #  3) global password (normalized to empty string if not present)
      def git_fusion_password
        @entry['password'] || url.password || global['password']
      end

      def git_fusion_user
        url_user = url.user unless url.scheme == 'scp'
        @entry['user'] || url_user || global['user']
      end

      # returns the perforce password (or the empty string if not found)
      def perforce_password
        @entry['perforce']['password'] ||
          @entry['password'] ||
          url.password ||
          global['perforce']['password'] ||
          global['password'] # normalized to the empty string if it doesn't exist
      end

      # returns the perforce username (or 'gitswarm' if not found)
      def perforce_user
        url_user = url.user unless url.scheme == 'scp'
        @entry['perforce']['user'] ||
          @entry['user'] ||
          url_user ||
          global['perforce']['user'] ||
          global['user'] # normalized to 'gitswarm' if it doesn't exist
      end

      # returns the perforce port or nil if not found
      def perforce_port
        # if we have an explicit port, use it!
        return @entry['perforce']['port'] if @entry['perforce']['port']

        # if no port was set attempt to scrape it from info output
        unless @info
          begin
            # only bother to run if we have an entry id
            @info = PerforceSwarm::GitFusion.run(@entry['id'], 'info') if @entry['id']
          rescue
            @info = ''
          end
        end

        # encrypted servers don't report the correct p4port (no ssl: prefix is present)
        # so we pull out both the port and encrypted flag and prefix if needed
        encrypted = @info =~ /^Server encryption: encrypted/                if @info
        port      = expand_perforce_port(@info[/^Server address: (.*)/, 1]) if @info
        port      = 'ssl:' + port                                           if port && encrypted && port !~ /^ssl:/
        port
      end

      # ensures that the given perforce port is properly expanded to include the required hostname
      def expand_perforce_port(port)
        return port unless port && !port.empty?
        expanded = port.dup
        host     = PerforceSwarm::GitFusion::URL.new(@entry['url']).host

        # remove leading : (as in :1666)
        expanded = expanded[1..-1] if expanded.start_with?(':')
        # expand bare port or ssl: with port (e.g. 1666, ssl:1666)
        expanded.gsub!(/^(ssl:)?(\d+)$/, '\1' + host + ':\2')
        # handle various incarnations of localhost (e.g. 127.0.0.1, localhost)
        expanded.gsub(/^(ssl:)?(localhost|127\.0\.0\.1|localhost\.localdom(ain)?)(:.+)?$/, '\1' + host + '\4')
      end

      def auto_create_configured?
        # ensure templates are strings and contain both a project-path and namespace substitution argument
        %w(path_template repo_name_template).each do |template|
          template = auto_create[template]
          return false unless template.is_a?(String) &&
                              template.include?('{project-path}') &&
                              template.include?('{namespace}')
        end

        # ensure the path template starts with //, contains at least one other slash and doesn't end in ...
        return false unless auto_create['path_template'] =~ %r{\A//[^/]+/.+(?<!\.\.\.)\z}
        true
      end

      def auto_create(setting = nil)
        settings = global['auto_create'].clone
        settings.merge!(@entry['auto_create']) if @entry['auto_create'] && @entry['auto_create'].is_a?(Hash)
        setting ? settings[setting] : settings
      end

      def url
        url = PerforceSwarm::GitFusion::URL.new(@entry['url'])
        # ensure we use the correct user
        url.user(@entry['user'] || url.user || global['user'])
      end

      def [](key)
        key = 'git_fusion_password' if key == 'password'
        key = 'git_fusion_user'     if key == 'user'

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
