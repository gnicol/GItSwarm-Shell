require 'P4'
require 'securerandom'
require_relative 'exceptions'
require_relative 'spec/client'

module PerforceSwarm
  module P4
    class Connection
      attr_reader :config

      def self.validate_config(config)
        fail '"config" must be a ConfigEntry' unless config.is_a?(PerforceSwarm::GitFusion::ConfigEntry)
        fail 'Your perforce configuration is missing a "port" entry.' unless config.perforce_port
        fail 'A Perforce user ID is required.' if !config.perforce_user || config.perforce_user.empty?
      end

      def initialize(config = nil, p4_dir = nil)
        p4_dir ||= File.join(Gitlab.config.gitlab['user_home'], 'p4')
        ENV['P4TICKETS'] = File.join(p4_dir, '.p4tickets') if File.exist?(p4_dir)
        ENV['P4TRUST']   = File.join(p4_dir, '.p4trust')   if File.exist?(p4_dir)
        @p4              = ::P4.new
        self.config      = config if config
      end

      def login(all = false)
        @ticket_unlocked = all

        fail PerforceSwarm::P4::IdentityNotFound, 'Login failed. No user specified.' unless @p4.user && !@p4.user.empty?
        args       = %w(login) + (all ? %w(-a -p) : %w(-p))
        self.input = password || ''
        begin
          result = run(*args)
        rescue P4Exception => e
          message = e.message

          # check for user existence
          not_exists = message.downcase.include?(
              "doesn't exist") || message.downcase.include?("has not been enabled by 'p4 protect'")
          raise PerforceSwarm::P4::IdentityNotFound, 'Login failed. ' + message if not_exists

          # invalid password
          if message.downcase.include?('password invalid')
            raise PerforceSwarm::P4::CredentialInvalid, 'Login failed. ' + message
          end

          # generic exception
          raise PerforceSwarm::P4::LoginException, 'Login failed. ' + message
        end

        # we can get several output blocks
        # we want the first block that looks like a ticket
        # if user has no password, the last block will be a message
        # if using external auth, early blocks could be trigger output
        # if talking to a replica, the last block will be a ticket for the master
        response = result.last || ''
        result.each do |line|
          next unless /^[A-F0-9]{32}$/ =~ line
          response = line
          break
        end

        # check if no password set for this user.
        # fail if a password was provided - succeed otherwise.
        if response.downcase.include?('no password set for this user')
          fail PerforceSwarm::P4::CredentialInvalid, 'Login failed. ' + response if password && !password.empty?
          return nil
        end

        unless response =~ /^[A-F0-9]{32}$/
          fail PerforceSwarm::P4::LoginException, 'Login failed. Unable to capture login ticket.'
        end
        @p4.password = response
      end

      # wrapper around the run method, which handles charset and untrusted server issues
      def run(*args)
        connect unless connected?
        info('start command:', args)
        last_input = input
        result = @p4.run(*args)
        # reset our stored input
        self.input = ''
        result
      rescue P4Exception => e
        # if we have no charset and the error was related to pointing at a unicode server,
        # set ourselves to use utf8 and re-run the command
        no_charset = !@p4.charset || @p4.charset.empty? || @p4.charset == 'none'
        if no_charset && e.message.include?('Unicode server permits only unicode enabled clients.')
          @p4.charset = 'utf8'
          self.input  = last_input
          return run(*args)
        end

        # if we failed due to an untrusted server, trust it and re-run
        if e.message.include?("To allow connection use the 'p4 trust' command") && !@has_trusted
          @has_trusted = true
          run('trust', '-y')
          # We must disconnect here after trust runs. It has been observed re-running login
          # results in an empty response from the login command
          disconnect
          self.input = last_input
          return run(*args)
        end

        # we encountered an error that we're unable to handle, so log and re-throw
        self.input = ''
        error('command failed:', e)
        raise e
      end

      def with_temp_client
        Dir.mktmpdir do |tmpdir|
          old_client = client
          p4_client_util = PerforceSwarm::P4::Spec::Client
          begin
            # create a temporary workspace/client, and set ourselves to use it
            spec = p4_client_util.create(self, temp_client_id, 'Root' => tmpdir)
            self.client = spec['Client']
            p4_client_util.save_temp(self, spec)
            # run the code we were asked to
            yield(tmpdir, spec, self)
          ensure
            # disconnect, which will delete our temporary client
            disconnect
            self.client = old_client
          end
        end
      end

      def temp_client_id
        'gitswarm-temp-' + SecureRandom.uuid
      end

      def input=(input)
        @p4.input = input
        @input    = input
      end

      def input(*args)
        if args.length > 0
          self.input = args[0]
          return self
        end
        @input
      end

      def user=(user)
        # guard against nil, false and the empty string - p4ruby borks on nil/false and uses the OS user on empty string
        fail PerforceSwarm::P4::IdentityNotFound, 'P4 user must be a non-empty string.' unless user && !user.empty?
        disconnect
        @p4.user = user
      end

      def user(*args)
        if args.length > 0
          self.user = args[0]
          return self
        end
        @p4.user
      end

      def port=(port)
        disconnect
        @p4.port = port
      end

      def port(*args)
        if args.length > 0
          self.port = args[0]
          return self
        end
        @p4.port
      end

      def client=(client)
        # if no client is specified, normally the host name is used.
        # this can collide with an existing depot or client name, so
        # we use a temp id to avoid errors.
        @p4.client = client || temp_client_id
        @client    = client
      end

      def client(*args)
        if args.length > 0
          self.client = args[0]
          return self
        end
        @client
      end

      def password=(password)
        # guard against nil and false
        fail PerforceSwarm::P4::LoginException, 'P4 password must be a string.' unless password
        disconnect
        @p4.password = password
        @password    = password
      end

      def password(*args)
        if args.length > 0
          self.password = args[0]
          return self
        end
        @password
      end

      def config=(config)
        Connection.validate_config(config)
        @config = config

        # reconfigure the internal P4 object
        self.port        = config.perforce_port
        self.user        = config.perforce_user
        self.password    = config.perforce_password
      end

      def config(*args)
        if args.length > 0
          self.config = args[0]
          return self
        end
        @config
      end

      def connect
        @p4.connect
        self
      end

      def connected?
        @p4.connected?
      end

      def disconnect
        @p4.disconnect if @p4.connected?
        self
      end

      def error(*args)
        log(args, true)
      end

      def info(*args)
        log(args)
      end

      def log(args, error = false)
        # include the same format of object ID as inspect would have provided
        message = ['P4 (' + format('%x', (object_id << 1)) + ')']
        message += args.map do |arg|
          arg = [arg.inspect, *arg.backtrace, "\n"].join("\n") if arg.is_a?(Exception)
          arg = arg.inspect unless arg.is_a?(String)
          arg
        end
        message = message.join(' ').strip
        error ? $logger.error(message) : $logger.info(message)
      end
    end
  end
end
