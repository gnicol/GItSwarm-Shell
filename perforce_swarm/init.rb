require_relative 'mirror'
require_relative '../lib/gitlab_custom_hook'
require_relative '../lib/gitlab_shell'
require_relative '../lib/gitlab_projects'

module PerforceSwarm
  # If everything else looks good, we want to do a mirror
  # push as the last step in the pre-recieve hook
  module GitlabCustomHook
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
  end

  # For ssh, do an early fetch from mirror to
  # make sure all the refs are up-to-date
  module GitlabShell
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

  module GitlabProjects
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
  prepend PerforceSwarm::GitlabCustomHook
end

class GitlabShell
  prepend PerforceSwarm::GitlabShell
end

class GitlabProjects
  prepend PerforceSwarm::GitlabProjects
end
