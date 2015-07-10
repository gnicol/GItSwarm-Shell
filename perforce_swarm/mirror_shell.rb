require 'optparse'

module PerforceSwarm
  class MirrorShell
    attr_accessor :config

    def initialize
      # the first arg is the command, the last arg the project name
      # we leave any other args alone and the individual handler can parse them as options
      @config       = GitlabConfig.new
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
      fail 'No project name was specified' unless @project_name && @full_path
      repo = Repo.new(@full_path)
      return false unless repo.mirrored?

      # deal with parsing out any known options
      wait_if_busy    = false
      min_outdated    = nil
      redis_on_finish = false
      last_fetched = Mirror.last_fetched(@full_path)
      op = OptionParser.new do |x|
        x.on('--wait-if-busy', 'Normally if a fetch is already running, we just return; this makes us wait') do
          wait_if_busy = true
        end
        x.on('--min-outdated=MANDATORY', Integer, 'Only fetches if at least X seconds since last fetch') do |n|
          min_outdated = n
        end
        x.on('--redis-on-finish', "Posts a #{config.redis_namespace}:queue:post_fetch event. Forces --wait-if-busy.") do
          redis_on_finish = true
        end
      end
      op.parse!(ARGV)

      wait_if_busy = true if redis_on_finish
      fail '--redis-on-finish is not compatible with --min-outdated' if redis_on_finish && min_outdated

      return false if !wait_if_busy && Mirror.fetch_locked?(@full_path)
      return false if min_outdated && last_fetched && last_fetched > (Time.now - min_outdated)

      begin
        Mirror.fetch!(@full_path)
        update_redis(true)
        true
      rescue
        update_redis(false)
        false
      end
    end

    def update_redis(success)
      queue = "#{config.redis_namespace}:queue:default"
      msg   = JSON.dump('class' => 'PerforceSwarm::PostFetchWorker', 'args' => [@full_path, success])
      if system(*config.redis_command, 'rpush', queue, msg, err: '/dev/null', out: '/dev/null')
        return true
      else
        $logger.error("GitSwarm: An unexpected error occurred (redis-cli returned #{$?.exitstatus}).")
        return false
      end
    end
  end
end
