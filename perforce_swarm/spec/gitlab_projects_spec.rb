require_relative 'spec_helper'
require_relative '../../lib/gitlab_projects'

describe GitlabProjects do
  before do
    GitlabConfig.any_instance.stub(repos_path: tmp_repos_path)
    FileUtils.mkdir_p(tmp_repos_path)
    $logger = double('logger').as_null_object
  end

  after do
    FileUtils.rm_rf(tmp_repos_path)
  end

  describe :fork_project do
    let(:source_repo_name) { File.join('source-namespace', repo_name) }
    let(:dest_repo) { File.join(tmp_repos_path, 'forked-to-namespace', repo_name) }
    let(:gl_projects_fork) { build_gitlab_projects('fork-project', source_repo_name, 'forked-to-namespace') }
    let(:gl_projects_import) do
      build_gitlab_projects('import-project', source_repo_name, 'https://github.com/randx/six.git')
    end

    before do
      gl_projects_import.exec
    end

    it "should not fork into a namespace that doesn't exist", override: true do
      gl_projects_fork.exec.should be_true
      File.exist?(dest_repo).should be_true
      File.exist?(File.join(dest_repo, '/hooks/pre-receive')).should be_true
      File.exist?(File.join(dest_repo, '/hooks/post-receive')).should be_true
    end
  end

  def build_gitlab_projects(*args)
    argv(*args)
    gl_projects = GitlabProjects.new
    gl_projects.stub(repos_path: tmp_repos_path)
    gl_projects.stub(full_path: File.join(tmp_repos_path, gl_projects.project_name))
    gl_projects
  end

  def argv(*args)
    args.each_with_index do |arg, i|
      ARGV[i] = arg
    end
  end

  def tmp_repos_path
    File.join(ROOT_PATH, 'tmp', 'repositories')
  end

  def repo_name
    'gitlab-ci.git'
  end
end
