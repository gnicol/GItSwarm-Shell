require_relative 'init'
require_relative 'git_fusion'
require_relative 'utils'

module PerforceSwarm
  class Repo
    class << self
      attr_accessor :error
    end

    # returns a hash mapping repo name to description for all repos for the given Git Fusion config block.
    # returns nil if something went wrong - check the 'error' method if you want details
    def self.list(id = nil)
      @error   = nil

      # parse the Git Fusion repos
      return parse_repos(PerforceSwarm::GitFusion.run(id, 'list'))
    rescue StandardError => e
      @error = e.message
      nil
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
