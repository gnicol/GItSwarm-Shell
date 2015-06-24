require 'rubygems'
require 'json'
require 'uri'
require_relative 'git_fusion'
require_relative 'utils'

module PerforceSwarm
  module GitFusion
    class Repo
      def self.list(git_fusion_url)
        # run the git fusion @list command
        output, _status = Utils.popen(['git', 'clone', PerforceSwarm::GitFusion.extend_url(git_fusion_url, 'list')])

        # parse out the Git Fusion repos
        parse_repos(output)
      end

      def self.parse_repos(git_output)
        repos = {}
        return repos unless git_output

        # iterate over each repo found and build a hash mapping repo name to description
        git_output.lines.each do |repo|
          if /^(?<name>[\w\-]+)\s+(push|pull)?\s+([\w\-]+)\s+(?<description>.+?)$/ =~ repo
            # TODO: do we need to ignore repos where we can't push?
            repos[name] = description.strip
          end
        end
        repos
      end
    end
  end
end
