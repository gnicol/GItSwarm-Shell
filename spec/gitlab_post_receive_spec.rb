require 'spec_helper'
require 'gitlab_post_receive'

describe GitlabPostReceive do
  let(:repository_path) { "/home/git/repositories" }
  let(:repo_name)   { 'dzaporozhets/gitlab-ci' }
  let(:repo_path)  { File.join(repository_path, repo_name) + ".git" }
  let(:gitlab_post_receive) { GitlabPostReceive.new(repo_path, 'key-123', 'wow') }

  before do
    GitlabConfig.any_instance.stub(repos_path: repository_path)
    Kernel.stub(system: true)
    GitlabNet.any_instance.stub(broadcast_message: { "message" => "test " * 10 + "message " * 10 })
  end

  describe :initialize do
    it { gitlab_post_receive.repo_path.should == repo_path }
    it { gitlab_post_receive.changes.should == 'wow' }
    it { gitlab_post_receive.exec }
  end
end
