require 'optparse'
require_relative '../lib/names_helper'

module PerforceSwarm
  class MirrorShell
    include NamesHelper

    attr_accessor :config, :command, :project_name, :full_path

    def initialize
      $logger.debug "gitswarm-mirror invoked with #{ARGV.length} args: '#{ARGV.join("', '")}'"

      # the first arg is the command, the last arg the project name
      # we leave any other args alone and the individual handler can parse them as options
      @config       = GitlabConfig.new
      @command      = ARGV.shift
      @project_name = extract_repo_name(ARGV.pop, config.repos_path.to_s)
      @full_path    = File.join(config.repos_path, "#{@project_name}.git") unless @project_name.nil?
    end

    def exec
      case @command
      when 'fetch'              then fetch
      when 'push'               then push
      when 'reenable_mirroring' then reenable_mirroring
      else
        $logger.warn "Attempt to execute invalid gitswarm-mirror command #{@command.inspect}."
        puts 'not allowed'
        false
      end
    rescue StandardError => e
      puts e.message
      $logger.error "gitswarm-mirror command #{@command.inspect} failed for: #{@project_name.inspect}\n#{e.message}"
      false
    end

    protected

    def push_all_refs
      # calculate all existing heads/tags. we start by running 'git show-ref --heads --tags'
      # we then split it into an array of entries. we wrap by making it colon not space delimited for sha:ref
      refs = Mirror.show_ref(@full_path)
      refs = refs.split("\n").map { |ref| ref.sub(' ', ':') }

      # push all of the detected refs to the remote mirror
      Mirror.push(refs, @full_path, require_block: false)
    end

    def push
      fail 'No project name was specified' unless @project_name && @full_path
      repo = Repo.new(@full_path)
      return true unless repo.mirrored?

      push_all_refs
      true
    rescue => ex
      puts ex.message
      $logger.error("gitswarm-mirror push failed. #{ex.class} #{ex.message}")
      false
    end

    def reenable_mirroring
      mirror_url = ARGV.pop
      fail 'No project name was specified' unless @project_name && @full_path
      fail 'No mirror URL provided.' unless mirror_url && !mirror_url.empty?

      # record whether our re-enable was successful - the following block
      # will not wait on the file lock, so if a re-enable is already in progress,
      # it will simply finish
      reenabled = false
      Mirror.with_reenable_lock(@full_path) do |error_file, fetch_error_file|
        begin
          repo = Repo.new(@full_path)
          return false if repo.mirrored?

          begin
            # remove any stale errors and prime with 'Unknown error.'
            File.write(error_file, 'Unknown error.')

            # set the mirror remote
            repo.mirror_url = mirror_url

            # fetch, eating any non-connectivity errors, re-throwing on connectivity problems
            begin
              Mirror.fetch!(@full_path)
            rescue => e
              if e.message.include?('Could not read from remote repository.')
                raise e
              else
                # an ignorable error occurred - clean up the fetch error log
                File.unlink(fetch_error_file) if File.exist?(fetch_error_file)
                $logger.error("Re-enabling mirror fetch error: #{mirror_url} #{@full_path}:\n#{e.message}")
              end
            end

            # push to the remote mirror, mark re-enable as success, clear any
            # re-enable errors, and push a redis event to re-enable mirroring in GitSwarm
            push_all_refs
            reenabled = true
            File.unlink(error_file)
            update_redis(true, 'PerforceSwarm::PostReenableWorker')
          rescue => e
            # we've encountered an error bad enough that we shouldn't re-enable
            $logger.error("Re-enabling mirror error: #{mirror_url} #{@full_path}:\n#{e.message}")
            File.write(error_file, e.message)
            raise e
          ensure
            # remove the mirror remote if the re-enable failed
            repo.mirror_url = nil unless reenabled
          end
        end
      end
      reenabled
    end

    def fetch
      fail 'No project name was specified' unless @project_name && @full_path
      repo = Repo.new(@full_path)
      return true unless repo.mirrored?

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

      return false if !wait_if_busy && (Mirror.fetch_locked?(@full_path) || Mirror.write_locked?(@full_path))
      return false if min_outdated && last_fetched && last_fetched > (Time.now - min_outdated)

      begin
        skip_if_pushing = !wait_if_busy && !redis_on_finish
        Mirror.fetch!(@full_path, skip_if_pushing)
        update_redis(true, 'PerforceSwarm::PostFetchWorker')  if redis_on_finish
      rescue => ex
        update_redis(false, 'PerforceSwarm::PostFetchWorker') if redis_on_finish
        raise ex
      end

      true
    rescue => ex
      puts ex.message
      $logger.error("gitswarm-mirror fetch failed. #{ex.class} #{ex.message}")
      false
    end

    def update_redis(success, message_class)
      queue = "#{config.redis_namespace}:queue:default"
      msg   = JSON.dump('class' => message_class, 'args' => [@full_path, success])
      if system(*config.redis_command, 'rpush', queue, msg, err: '/dev/null', out: '/dev/null')
        return true
      else
        $logger.error("GitSwarm: An unexpected error occurred (redis-cli returned #{$?.exitstatus}).")
        return false
      end
    end
  end
end
