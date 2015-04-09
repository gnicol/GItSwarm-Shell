require_relative 'spec_helper'
require_relative '../mirror'

describe PerforceSwarm::Mirror do
  before do
    FileUtils.mkdir_p(tmp_repos_path)
    GitlabConfig.any_instance.stub(repos_path: tmp_repos_path)
  end

  after do
    FileUtils.rm_rf(tmp_repos_path)
  end

  let(:tmp_repos_path) { File.join(ROOT_PATH, 'tmp', 'repositories') }
  let(:repo_name) { 'gitswarm.git' }

  subject do
    PerforceSwarm::Mirror
  end

  describe :show_ref do
    let(:gl_projects_create) do
      build_gitlab_projects('import-project', repo_name, 'https://github.com/randx/six.git')
    end

    it 'should show valid ref output' do
      (gl_project = gl_projects_create).exec
      refs = subject.send(:show_ref, gl_project.full_path)

      refs.should_not be_nil
      refs.should_not be_empty
      refs.split("\n").length.should be > 0
      refs.split("\n").each do |ref|
        ref.should =~ /^\h{40} \S+$/
      end
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
end
