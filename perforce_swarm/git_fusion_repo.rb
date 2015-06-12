require 'rubygems'
require 'json'
require_relative 'git_fusion_utils'

module PerforceSwarm
  class GitFusionRepo
    class << self
      def list(git_fusion_url)
        # validate the git_fusion_url
        return {} unless git_fusion_url?(git_fusion_url)

        # add our @list command
        git_fusion_url += ':@list'
        output, status = GitFusionUtils.popen(['git', 'clone', git_fusion_url])

        # parse out the Git Fusion repos
        parse_repos(output)
      end

      def parse_repos(git_output)
        return {} unless git_output && !git_output.empty? && git_output.index("\n")

        output = git_output.split("\n")
        return {} unless output && !output.empty? && output.index('fatal: Could not read from remote repository.')

        # slice out the bits we don't need
        output = output.slice(1, output.index('fatal: Could not read from remote repository.') - 1)

        # no repos were in the list
        return {} if output.empty?

        # iterate over each repo found and build a hash mapping repo name to description
        repos = {}
        output.each do |repo|
          if /^(?<name>[\w\-]+)\s+(?<perms>push|pull)?\s+(?<encoding>[\w\-]+)\s+(?<description>.+?)$/ =~ repo
            # TODO: do we need to ignore repos where we can't push?
            repos[name] = description
          end
        end
        repos
      end

      def git_fusion_url?(url)
        # user@host[:port] - we don't accept anything with a path
        /^([\w+\-]+)@([\w\-\.]+)(:(\d+))?$/ =~ url
      end
    end
  end
end