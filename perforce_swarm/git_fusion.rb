require 'uri'

module PerforceSwarm
  module GitFusion
    # extends a plain git url with a Git Fusion extended command, optional repo and optional extras
    class URL
      attr_accessor :url, :extra, :command
      attr_reader :command, :scheme, :repo

      VALID_SCHEMES  = %w(http https ssh)
      VALID_COMMANDS = %w(help info list status wait)

      def initialize(url)
        parsed = parse(url)

        fail "Invalid URL specified: #{url}." if parsed.host.nil?

        # parse out the user/password, host and port (if applicable)
        @scheme = parsed.scheme
        if @scheme == 'scp'
          @url = parsed.user + '@' + parsed.host
        else
          host = parsed.host + (parsed.port && parsed.port != parsed.default_port ? ':' + parsed.port.to_s : '')
          @url = parsed.scheme + '://' + (parsed.userinfo ? parsed.userinfo + '@' : '') + host
        end

        # turf any leading or trailing slashes, and call it a day if there is no remaining path
        path = parsed.path.gsub(%r{^/|/$}, '')
        return if path.empty?

        # parse out pieces of @-syntax, if present
        if path.start_with?('@')
          @command, @repo, @extra = path.split('@')[1..-1]
        else
          # only repo is specified in this case
          @repo = path
        end
      end

      def parse(url)
        # runs regex, swap to named params
        fail 'No URL provided.' unless url

        # extract the scheme - no scheme/protocol supplied means it's an scp-style git URL
        %r{^(?<scheme>[A-Za-z]+)://.+$} =~ url
        fail "Invalid URL scheme specified: #{scheme}." unless scheme.nil? || VALID_SCHEMES.index(scheme)

        # explicitly add the scp protocol and fix up the path spec if it uses a colon (needs to be a slash)
        unless scheme
          if %r{^(?<trimmed>([^@]+@)?([^/:]+))(?<delim>[/:])(?<path>.*)$} =~ url
            @delimiter = delim
            url        = trimmed + '/' + path
          else
            @delimiter = ':'
          end
          url = 'scp://' + url
        end

        # returns a parsed URI object or throws an exception if it's invalid
        parsed = URI.parse(url)
        fail 'User must be specified if scp syntax is used.' if parsed.scheme == 'scp' && !parsed.user

        parsed
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
        fail "Unknown command: #{command}" unless URL.valid_command?(command)
        @command = command
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

      def clear_path
        @repo = nil
        clear_command
      end

      def clear_command
        @command = nil
        @extra   = nil
      end

      def to_s
        # build and put @ and params in the right spots
        str = @url + delimiter    if pathed?
        str += '@' + @command    if @command
        # TODO: if we only have a repo, don't @-ify it
        str += '@' + @repo       if @repo
        # TODO: if we only have an extra (no command or repo) then throw
        str += '@' + @extra.to_s if @extra
        str
      end

      def delimiter
        @delimiter || '/'
      end

      def pathed?
        @command || @repo || @extra
      end
    end
  end
end
