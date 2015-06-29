require_relative 'init'
require_relative 'git_fusion'
require_relative 'utils'

module PerforceSwarm
  module GitFusion
    class Repo
      class << self
        attr_accessor :error
      end

      # returns a hash mapping repo name to description for all repos defined at the configured (or specified)
      # base URL. returns nil if something went wrong - check the 'error' method if you want details
      def self.list(url = nil)
        url    ||= GitlabConfig.new.git_fusion['url']
        @error   = nil

        # run the git fusion @list command
        output = PerforceSwarm::GitFusion::URL.new(url).clear_path.command('list').run

        # parse the Git Fusion repos
        return parse_repos(output)
      rescue StandardError => e
        @error = e.message
        nil
      end

      # returns the message from the last error received, or nil if no errors were found
      def self.error
        @error
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
