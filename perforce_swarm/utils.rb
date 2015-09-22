require 'open3'

module PerforceSwarm
  class Utils
    def self.popen(cmd, path = nil, stream_output = nil)
      unless cmd.is_a?(Array)
        fail 'System commands must be given as an array of strings'
      end

      path  ||= Dir.pwd
      vars    = { 'PWD'                 => path,
                  'GIT_SSH_COMMAND'     => 'ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no',
                  'GIT_TERMINAL_PROMPT' => '0',
                  'PATH'                => "#{RbConfig::CONFIG['bindir']}:#{ENV['PATH']}"
      }

      # set the LANG and LC_ALL environment variables if we can determine a locale
      begin
        locale         = determine_user_locale
      rescue
        # no locale was determined
        locale = nil
      end
      vars['LANG']   = locale
      vars['LC_ALL'] = locale

      options = { chdir: path }

      FileUtils.mkdir_p(path) unless File.directory?(path)

      cmd_output = ''
      cmd_status = 0
      Open3.popen2e(vars, *cmd, options) do |stdin, stdout_and_stderr, wait_thr|
        # some apps won't fully start till stdin is closed up; we don't use it so close it
        stdin.close

        # read a line at a time from stdout/stderr and capture/report it as needed
        # be aware git-fusion uses 0x0D, \r to stack progress output and 0x0A, \n to really line break between hunks.
        line = ''
        stdout_and_stderr.each_char do |char|
          cmd_output << char
          line << char

          # if we're not on a newline character just capture into line and continue
          # note this means the \n in a \r\n sequence gets processed as its own line
          # we do not however normally expect to encounter \r\n sequences.
          next unless char == "\n" || char == "\r"

          # strip the remote lead-in and print/yield as needed if the line has content
          line.gsub!(/^remote: /, '')
          print line if !line.empty? && stream_output
          yield line if !line.empty? && block_given?
          line = ''
        end

        # if there was data left in line print/yield as needed if the line has content
        line.gsub!(/^remote: /, '')
        print line if !line.empty? && stream_output
        yield line if !line.empty? && block_given?

        cmd_status = wait_thr.value.exitstatus
      end

      # for the non-streamed output, normalize line-endings to \n
      # this makes it much easier to play with them using regex or to log them
      cmd_output.gsub!(/\r\n|\r/, "\n")

      [cmd_output, cmd_status]
    end

    # Determines the locale variable to set for the current user, and returns
    # - the value from environment of the current user
    # - en_US.utf8/en_CA/en_GB if one exists in the list of available locales
    # - the first utf8 value found in the list of locales
    # If no valid utf8 value is found we fail out
    def self.determine_user_locale
      # Read the ~/.bashrc for the current user and return the value of LANG or LC_ALL if they have it
      bashrc_path   = File.expand_path('~/.bashrc')
      bashrc        = File.read(bashrc_path) if File.readable?(bashrc_path)
      bashrc_locale = bashrc[/^\s*export\s*(LANG|LC_ALL)\s*=\s*([^\#]+).*$/, 2] if bashrc
      return bashrc_locale.gsub(/['"]/, '').strip if bashrc_locale

      # If we can't scrape a usable variable value from the current user; this is our preferred fallbacks
      preferred_locales = %w(en_US.utf8 en_US.UTF-8 en_CA.utf8 en_CA.UTF-8 en_GB.utf8 en_GB.UTF-8)

      # A pattern to check if a given locale is usable or not
      regex = /\.(utf8|UTF-8)$/

      # If the active user's variable is a workable value, use that.
      # Otherwise, we'll list the supported locals to see if we can find a workable one.
      lang = ENV['LANG'] || ENV['LC_ALL']
      if !lang || !lang.match(regex)
        # use locale -a to determine which languages are supported (we filter for only UTF-8 entries)
        out, status = Open3.capture2e(*%w(locale -a))
        fail "Running locale -a to detect supported LANG or LC_ALL values failed: #{out}" unless status.success?
        locales = out.encode('UTF-8', invalid: :replace).split("\n").select { |locale| locale.match(regex) }
        # take the first preferred locale; if no preferred locales are present, just use the first valid locale
        # note this could still leave variable as nil if no valid locales were present
        lang = (preferred_locales & locales).first || locales.first
      end

      # Fail if specified variable is not set for current user or no UTF-8 values were found in the list of locales
      fail 'Could not determine a workable locale setting for LANG or LC_ALL.' if !lang || !lang.match(regex)
      lang
    end
  end
end
