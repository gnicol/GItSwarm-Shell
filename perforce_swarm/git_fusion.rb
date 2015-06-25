require 'tmpdir'
require 'uri'
require_relative 'utils'

module PerforceSwarm
  module GitFusion
    # extends a plain git url with a Git Fusion extended command, optional repo and optional extras
    class URL
      attr_accessor :url, :delimiter
      attr_reader :scheme
      attr_writer :extra

      VALID_SCHEMES  = %w(http https ssh)
      VALID_COMMANDS = %w(help info list status wait)

      def initialize(url)
        parse(url)
      end

      def run(stream_output = nil, &block)
        fail 'run requires a command' unless command
        Dir.mktmpdir do |temp|
          silenced = false
          output   = ''
          Utils.popen(['git', '-c', 'core.askpass=true', 'clone', '--', to_s], temp) do |line|
            silenced ||= line =~ /^fatal: /
            next if line =~ /^Cloning into/ || silenced
            output += line
            print line       if stream_output
            block.call(line) if block
          end
          return output.chomp
        end
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

        # parse out the user/password, host and port (if applicable)
        @scheme = parsed.scheme
        if @scheme == 'scp'
          self.url = parsed.user + '@' + parsed.host
        else
          host     = parsed.host + (parsed.port && parsed.port != parsed.default_port ? ':' + parsed.port.to_s : '')
          self.url = parsed.scheme + '://' + (parsed.userinfo ? parsed.userinfo + '@' : '') + host
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
      rescue URI::Error
        raise "Invalid URL specified: #{url}."
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
        str  = url
        str += delimiter        if pathed?
        str += '@' + command    if command
        str += '@'              if command && repo
        str += repo             if repo
        str += '@' + extra.to_s if extra
        str
      end

      def delimiter
        @delimiter || '/'
      end

      def pathed?
        command || repo || extra
      end
    end
  end
end
