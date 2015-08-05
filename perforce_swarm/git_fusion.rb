require 'tmpdir'
require 'uri'
require_relative 'config'
require_relative 'utils'

module PerforceSwarm
  module GitFusion
    class RunError < RuntimeError
    end

    class RunAccessError < RunError
    end

    def self.validate_entries(min_version = nil)
      fail "Invalid min_version specified: #{min_version}"  if min_version && !Gem::Version.correct?(min_version)
      min_version = Gem::Version.new(min_version)               if min_version

      # For every valid Git Fusion instance configuration attempt connection
      # and save appropriate result into an array for further processing
      results = {}
      PerforceSwarm::GitlabConfig.new.git_fusion_entries.each do |id, config|
        begin
          # prime valid to false; should something go awry it stays there
          results[id]            = { valid: false, config: config, id: id }
          # verify we can run info and then parse out the version details
          results[id][:info]    = run(id, 'info')
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

    def self.run(id, command, repo: nil, extra: nil, stream_output: nil, &block)
      fail 'run requires a command' unless command
      config = PerforceSwarm::GitlabConfig.new.git_fusion_entry(id)
      url    = PerforceSwarm::GitFusion::URL.new(config['url']).command(command).repo(repo).extra(extra)
      Dir.mktmpdir do |temp|
        silenced = false
        output   = ''
        Utils.popen(['git', *git_config_params(config), 'clone', '--', url.to_s], temp) do |line|
          # throw if we get an error different from 'repository..'
          fail RunAccessError, $LAST_MATCH_INFO['error'] if line =~ /^fatal: (?!repository)(?<error>.*)$/
          silenced ||= line =~ /^fatal: /
          next if line =~ /^Cloning into/ || silenced
          output += line
          print line       if stream_output
          block.call(line) if block
        end
        return output.chomp
      end
    end

    def self.git_config_params(config)
      params = ['core.askpass=' + File.join(__dir__, 'bin', 'git-provide-password'), *config['git_config_params']]
      params.flat_map { |value| ['-c', value] if value && !value.empty? }.compact
    end

    # extends a plain git url with a Git Fusion extended command, optional repo and optional extras
    class URL
      attr_accessor :url, :delimiter
      attr_reader :scheme, :password
      attr_writer :extra, :strip_password, :user

      VALID_SCHEMES  = %w(http https ssh)
      VALID_COMMANDS = %w(help info list status wait)

      def initialize(url)
        @strip_password = true
        @user           = nil
        parse(url)
      end

      # parses the given URL, and sets instance variables for base url (without path), command, repo
      # and extra parameters if given - raises an exception if:
      #  * no URL is provided
      #  * an invalid scheme is provided (http, https and ssh are supported)
      #  * missing a username in scp-style urls (e.g. user@host)
      #  * the URL is otherwise invalid, as determined by ruby's URI.parse method
      def parse(url)
        # reset the stored delimiter, command, repo and extra before parsing, in case we're being called multiple times
        self.delimiter = nil
        self.command   = nil
        self.repo      = nil
        self.extra     = nil

        fail 'No URL provided.' unless url

        # extract the scheme - no scheme/protocol supplied means it's an scp-style git URL
        %r{^(?<scheme>\w+)://.+$} =~ url
        fail "Invalid URL scheme specified: #{scheme}." unless scheme.nil? || VALID_SCHEMES.index(scheme)

        # explicitly add the scp protocol and fix up the path spec if it uses a colon (needs to be a slash)
        unless scheme
          if %r{^(?<trimmed>([^@]+@)?([^/:]+))(?<delim>[/:])(?<path>.*)$} =~ url
            self.delimiter = delim
            url = trimmed + '/' + path
          else
            self.delimiter = ':'
          end
          url = 'scp://' + url
        end

        # parses a URI object or throws an exception if it's invalid
        parsed = URI.parse(url)

        fail 'User must be specified if scp syntax is used.' if parsed.scheme == 'scp' && !parsed.user
        fail "Invalid URL specified: #{url}." if parsed.host.nil?

        # construct the base URL, grabbing the specified user, if any
        @scheme = parsed.scheme
        if @scheme == 'scp'
          @user    = parsed.user
          self.url = parsed.user + '@' + parsed.host
        else
          self.url  = parsed.scheme + '://' + (parsed.userinfo ? parsed.userinfo + '@' : '') + host(parsed)
          @user     = parsed.user
          @password = parsed.password
        end

        # turf any leading or trailing slashes, and call it a day if there is no remaining path
        path = parsed.path.gsub(%r{^/|/$}, '')
        return if path.empty?

        # parse out pieces of @-syntax, if present
        if path.start_with?('@')
          segments     = path[1..-1].split('@', 3)
          self.command = segments[0]
          self.repo    = segments[1]
          self.extra   = segments[2]
        else
          # only repo is specified in this case
          self.repo = path
        end
      rescue URI::Error => e
        raise "Invalid URL specified: #{url} : #{e.message}."
      end

      def self.valid?(url)
        new(url)
        true
      rescue
        return false
      end

      def self.valid_command?(command)
        VALID_COMMANDS.index(command)
      end

      def command=(command)
        fail "Unknown command: #{command}" unless !command || URL.valid_command?(command)
        @command = command
      end

      def command(*args)
        if args.length > 0
          self.command = args[0]
          return self
        end
        @command
      end

      def repo=(repo)
        if repo.is_a? String
          # set the repo to the string given
          @repo = repo
        elsif repo
          # repo is true, throw if we didn't parse a repo from the original URL
          fail 'Repo expected but none given.' unless @repo
        else
          # repo is false, so remove whatever we parsed from the original repo
          @repo = nil
        end
      end

      def repo(*args)
        if args.length > 0
          self.repo = args[0]
          return self
        end
        @repo
      end

      def extra(*args)
        if args.length > 0
          self.extra = args[0]
          return self
        end
        @extra
      end

      def strip_password(*args)
        if args.length > 0
          self.strip_password = args[0]
          return self
        end
        @strip_password
      end

      def user(*args)
        if args.length > 0
          self.user = args[0]
          return self
        end
        @user
      end

      def clear_path
        self.repo = nil
        clear_command
        self
      end

      def clear_command
        self.command = nil
        self.extra   = nil
        self
      end

      def to_s
        fail 'Extra requires both command and repo to be specified.' if extra && (!command || !repo)

        # build and put @ and params in the right spots
        str  = build_url
        str += delimiter        if pathed?
        str += '@' + command    if command
        str += '@'              if command && repo
        str += repo             if repo
        str += '@' + extra.to_s if extra
        str
      end

      def build_url
        if scheme != 'scp'
          # parse and set username/password fields as needed - we've already extracted user/password during init
          parsed          = URI.parse(url)
          parsed.user     = @user
          parsed.password = @password

          # build and include the correct userinfo
          userinfo  = parsed.user ? parsed.user : ''
          userinfo += parsed.password && !strip_password ? ':' + parsed.password : ''
          str       = parsed.scheme + '://' + (!userinfo.empty? ? userinfo + '@' : '') + host(parsed)
        else
          # url is simply user@host
          parsed = url.split('@', 2)
          str    = @user + '@' + parsed[1]
        end
        str
      end

      def delimiter
        @delimiter || '/'
      end

      def pathed?
        command || repo || extra
      end

      protected

      def host(url)
        url.host + (url.port && url.port != url.default_port ? ':' + url.port.to_s : '')
      end
    end
  end
end
