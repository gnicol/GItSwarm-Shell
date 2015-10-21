require_relative 'init'
require 'timeout'

module PerforceSwarm
  class MirrorLockSocketServer
    def initialize(repo_path)
      @repo = PerforceSwarm::Repo.new(repo_path)
    end

    def start
      # If the repo isn't mirrored; simply set the ENV to indicate
      # everything is ok to receive-pack and return.
      unless @repo.mirrored?
        ENV['WRITE_LOCK_SOCKET'] = PerforceSwarm::Mirror::NOT_MIRRORED
        return
      end

      push_lock = nil # keeping the handle scoped outside the thread is important!
      @lock_socket = "#{@repo.path}/mirror_push-#{Process.pid}.socket"
      ENV['WRITE_LOCK_SOCKET'] = @lock_socket
      File.unlink(@lock_socket) if File.exist?(@lock_socket)
      @thread = Thread.new do
        begin
          Socket.unix_server_loop(@lock_socket) do |socket|
            begin
              # just encase an evil do-er connects; only wait 5 seconds for a command don't block forever
              command = nil
              Timeout.timeout 5 do
                command = socket.gets.strip
              end

              case command
              when 'LOCK'
                push_lock = PerforceSwarm::Mirror.write_lock(@repo.path)
              when 'UNLOCK'
                PerforceSwarm::Mirror.write_unlock(@repo.path)
              else
                # ignore unknown commands
                socket.puts 'UNKNOWN'
                $logger.error "Lock socket received invalid command: #{command}"
                next
              end

              socket.puts "#{command}ED"
            rescue Timeout::Error
              socket.puts 'TIMEOUT'
              $logger.error 'Lock socket timed out waiting for a command'
              next
            ensure
              socket.flush
              socket.close
            end
          end
        rescue Errno::ENOENT => e
          # the unix_server_loop attempts to clean up the socket file but its unreliable so we also clean it up
          # just eat the unlink exception that occurs if we beat them to the punch; re-raise anything else
          raise e unless e.message =~ /@ unlink/
        end
      end
      @thread.abort_on_exception = true
    end

    def stop
      if @repo.mirrored?
        @thread.kill
        FileUtils.safe_unlink(@lock_socket)
      end
    end
  end
end
