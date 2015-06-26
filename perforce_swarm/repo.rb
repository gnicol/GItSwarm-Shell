require_relative 'git_fusion'
require_relative 'utils'

module PerforceSwarm
  module GitFusion
    class Repo
      def self.list(git_fusion_url)
        # run the git fusion @list command
        output = PerforceSwarm::GitFusion::URL.new(git_fusion_url).clear_path.command('list').run

        # parse out the Git Fusion repos
        parse_repos(output)
      end

      def self.parse_repos(git_output)
        repos = {}
        return repos unless git_output

        # iterate over each repo found and build a hash mapping repo name to description
        git_output.lines.each do |repo|
          if /^(?<name>[\w\-]+)\s+(push|pull)?\s+([\w\-]+)\s+(?<description>.+?)$/ =~ repo
            repos[name] = description.strip
          end
        end
        repos
      end
    end
  end
end
