require_relative 'mirror'
require_relative '../lib/gitlab_custom_hook'
require_relative '../lib/gitlab_shell'
require_relative '../lib/gitlab_projects'

module PerforceSwarm
  # If everything else looks good, we want to do a mirror
  # push as the last step in the pre-recieve hook
  module GitlabCustomHookExtension
    def pre_receive(changes, repo_path)
      return false unless super

      # Transform the changes into an array of pushable ref updates
      refs = []
      changes.split(/\r\n|\r|\n/).each do |refline|
        _src, tgt, ref = refline.strip.split
        refspec = (tgt.match(/^0+$/) ? '' : tgt) + ':' + ref
        refs.push(refspec)
      end
      Mirror.push(refs, repo_path)
      true
    rescue Mirror::Exception
      return false
    end

    def post_receive(changes, repo_path)
      # if this repo is mirroring, UNLOCK as we know refs have been updated at this point
      Mirror.lock_socket('UNLOCK') if Mirror.mirror_url(repo_path)
      super
    end
  end

  module GitlabNetExtension
    def check_access(cmd, repo, actor, changes)
      # Store the repo and command so we can use it in other methods
      @repo  = repo
      @cmd   = cmd
      status = super
      @repo  = nil
      @cmd   = nil
      status
    end

    def request(method, url, params = {})
      # Have the api check for a service user if this is a mirror repo
      if @repo
        mirror = Mirror.mirror_url(File.join(config.repos_path, @repo))
        params['check_service_user'] = true if mirror
      end

      response = super

      # Custom error handling for 400 errors, because GitLab's error
      # handling doesn't make it back to the client properly
      if response.code == '400'
        puts "#{format('%04x', response.body.bytesize + 8)}ERR #{response.body}"
      end

      response
    end
  end

  # For ssh, do an early fetch from mirror to
  # make sure all the refs are up-to-date
  module GitlabShellExtension
    def process_cmd
      repo_full_path = File.join(repos_path, repo_name)

      # push errors are fatal but pull errors are ignorable
      if @git_cmd == 'git-receive-pack'
        Mirror.fetch!(repo_full_path)
      else
        Mirror.fetch(repo_full_path)
      end

      super
    rescue Mirror::Exception => e
      unless @git_cmd == 'git-receive-pack'
        puts "#{format('%04x', e.message.bytesize + 8)}ERR #{e.message}"
      end
      raise Mirror::Exception, e.message
    end

    def exec_cmd(*args)
      if args[0] == 'git-receive-pack'
        args[0] = File.join(ROOT_PATH, 'perforce_swarm', 'bin', 'swarm-receive-pack')
      end
      super(*args)
    end
  end

  module GitlabProjectsExtension
    def create_branch
      branch_name = ARGV[0]
      ref         = ARGV[1] || 'HEAD'
      Mirror.push(["#{ref}:#{branch_name}"], full_path)
      super
    rescue Mirror::Exception
      return false
    end

    def rm_branch
      Mirror.push([":#{ARGV.first}"], full_path)
      super
    rescue Mirror::Exception
      return false
    end
  end
end

class GitlabCustomHook
  prepend PerforceSwarm::GitlabCustomHookExtension
end

class GitlabNet
  prepend PerforceSwarm::GitlabNetExtension
end

class GitlabShell
  prepend PerforceSwarm::GitlabShellExtension
end

class GitlabProjects
  prepend PerforceSwarm::GitlabProjectsExtension
end
