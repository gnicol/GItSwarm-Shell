module PerforceSwarm
  module GitFusion
    def self.valid_url?(url)
      return false if url.nil?
      %r{^([\w+\-]+)@([\w\-\.]+)(:(\d+))?(\/[\w-]+)?$} =~ url || url.match(URI.regexp(%w(http https)))
    end

    def self.valid_command?(command)
      %w(help info list status wait).index(command)
    end

    # extends a plain git url with a Git Fusion extended command, optional repo and optional extras
    def self.extend_url(original, command, repo = false, extra = false)
      fail 'Invalid URL given to extend' unless valid_url?(original)
      fail 'Invalid command given to extend' unless valid_command?(command)

      original.chomp!('/')
      extended_path = ':@' + command

      if repo
        parsed_repo = repo(original)
        fail 'No repository found in git URL' unless parsed_repo && !parsed_repo.empty?
        extended_path += '@' + parsed_repo
        original = remove_repo(original)
      else
        # remove the repo from the URL, if present
        original = remove_repo(original)
      end

      extended_path += '@' + extra if extra
      original + extended_path
    end

    def self.repo(url)
      url  = url.gsub('://', '')
      repo = url.index('/') ? url.gsub('://', '').slice((url.index('/') + 1)..-1) : nil
      repo.nil? || repo.empty? ? nil : repo
    end

    def self.remove_repo(url)
      repo = repo(url)
      repo.nil? ? url.chomp('/') : url.slice(0, url.index('/' + repo))
    end
  end
end
