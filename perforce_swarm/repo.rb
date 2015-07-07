require_relative 'init'
require_relative 'git_fusion'
require_relative 'utils'

module PerforceSwarm
  class Repo
    class << self
      attr_accessor :error
    end

    # returns a hash mapping repo name to description for all repos for the given Git Fusion config entry
    def self.list(id = nil)
      parse_repos(PerforceSwarm::GitFusion.run(id, 'list'))
    end

    # largely a separate method for testability
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
