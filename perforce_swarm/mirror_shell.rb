require 'optparse'

module PerforceSwarm
  class MirrorShell
    def initialize
      # the first arg is the command, the last arg the project name
      # we leave any other args alone and the individual handler can parse them as options
      @command      = ARGV.shift
      @project_name = ARGV.pop
      @repos_path   = GitlabConfig.new.repos_path
      @full_path    = File.join(@repos_path, @project_name) unless @project_name.nil?
    end

    def exec
      case @command
      when 'fetch' then fetch
      else
        $logger.warn "Attempt to execute invalid gitswarm-mirror command #{@command.inspect}."
        puts 'not allowed'
        false
      end
    rescue StandardError => e
      $logger.error "gitswarm-mirror command #{@command.inspect} failed for: #{@project_name.inspect}\n#{e.message}"
      false
    end

    protected

    def fetch
      fail 'No project name was specified'      unless @project_name && @full_path
      fail 'Invalid project name was specified' unless File.file?(File.join(@full_path, 'config'))
      return false unless Mirror.mirror_url(@full_path)

      # deal with parsing out any known options
      wait_if_busy = false
      min_outdated = nil
      last_fetched = Mirror.last_fetched(@full_path)
      op = OptionParser.new do |x|
        x.on('--wait-if-busy', 'Normally if a fetch is already running, we just return; this makes us wait') do
          wait_if_busy = true
        end
        x.on('--min-outdated=MANDATORY', Integer, 'Only fetches if at least X seconds since last fetch') do |n|
          min_outdated = n
        end
      end
      op.parse!(ARGV)

      return false if !wait_if_busy && Mirror.fetch_locked?(@full_path)
      return false if min_outdated && last_fetched && last_fetched > (Time.now - min_outdated)

      Mirror.fetch!(@full_path)
      true
    end
  end
end
