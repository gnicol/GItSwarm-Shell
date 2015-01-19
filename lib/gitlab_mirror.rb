require_relative 'gitlab_init'

class GitlabMirror
  attr_reader :config

  def initialize
    @config = GitlabConfig.new
  end

  def pull
    system("echo shoulda pulled! >> /tmp/itran");
  end
end
