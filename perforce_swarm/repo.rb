require 'rubygems'
require 'json'
require 'uri'
require_relative 'utils'

module PerforceSwarm
  module GitFusion
    class Repo
      def self.list(git_fusion_url)
        # validate the git_fusion_url
        return {} unless GitFusion.valid_url?(git_fusion_url)

        # add our @list command
        git_fusion_url += ':@list'
        output, _status = Utils.popen(['git', 'clone', git_fusion_url])

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
