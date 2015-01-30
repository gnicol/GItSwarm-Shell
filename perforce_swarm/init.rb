require_relative 'mirror'
require_relative '../lib/gitlab_custom_hook'
require_relative '../lib/gitlab_shell'

module PerforceSwarm
  # If everything else looks good, we want to do a mirror
  # push as the last step in the pre-recieve hook
  module GitlabCustomHook
    def pre_receive(changes, repo_path)
      return false unless super

      PerforceSwarm::Mirror.push(changes, repo_path)
      true
    rescue PerforceSwarm::Mirror::Exception
      return false
    end
  end

  # For ssh, do an early fetch from mirror to
  # make sure all the refs are up-to-date
  module GitlabShell
    def process_cmd
      repo_full_path = File.join(repos_path, repo_name)

      PerforceSwarm::Mirror.fetch(repo_full_path)
      super
    rescue PerforceSwarm::Mirror::Exception => e
      raise GitlabShell::DisallowedCommandError, e.message
    end
  end
end

class GitlabCustomHook
  prepend PerforceSwarm::GitlabCustomHook
end

class GitlabShell
  prepend PerforceSwarm::GitlabShell
end
