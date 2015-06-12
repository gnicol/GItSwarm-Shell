require 'open3'

module PerforceSwarm
  class GitFusionUtils
    class << self
      def popen(cmd, path = nil, stream_output = nil)
        unless cmd.is_a?(Array)
          fail 'System commands must be given as an array of strings'
        end

        path  ||= Dir.pwd
        vars    = { 'PWD' => path }
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
    end
  end
end
