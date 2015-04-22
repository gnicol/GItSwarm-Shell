require_relative 'spec_helper'
require_relative '../mirror'

describe PerforceSwarm::Mirror do
  before do
    FileUtils.mkdir_p(tmp_repos_path)
    GitlabConfig.any_instance.stub(repos_path: tmp_repos_path)
  end

  after do
    ENV['WRITE_LOCK_SOCKET'] = nil
    FileUtils.rm_rf(tmp_repos_path)
  end

  let(:tmp_repos_path) { File.join(ROOT_PATH, 'tmp', 'repositories') }
  let(:test_repo_bundle) { File.join(ROOT_PATH, 'perforce_swarm', 'spec', '6-branch-4-tag-repo.bundle') }
  let(:repo_name) { 'gitswarm.git' }

  subject do
    PerforceSwarm::Mirror
  end

  describe :push do
    let(:gl_projects_create) do
      build_gitlab_projects('import-project', repo_name, test_repo_bundle)
    end

    it 'should fail when require_block is not set to false, and no block is given' do
      (gl_project = gl_projects_create).exec
      expect { subject.send(:push, [], gl_project.full_path) }.to raise_error(ArgumentError)
      expect { subject.send(:push, [], gl_project.full_path, require_block: true) }.to raise_error(ArgumentError)
    end

    it 'should fail when receive_pack is set, and no lock socket is available in the environment' do
      (gl_project = gl_projects_create).exec
      expect { subject.send(:push, [], gl_project.full_path, receive_pack: true) }
        .to raise_error(PerforceSwarm::Mirror::Exception, /WRITE_LOCK_SOCKET is required/)
    end

    it 'should fail when receive_pack is set, and ENV[WRITE_LOCK_SOCKET] is invalid' do
      (gl_project = gl_projects_create).exec
      ENV['WRITE_LOCK_SOCKET'] = "#{File.realpath(tmp_repos_path)}/no_socket"
      expect { subject.send(:push, [], gl_project.full_path, receive_pack: true) }
        .to raise_error(PerforceSwarm::Mirror::Exception, /WRITE_LOCK_SOCKET is invalid/)
    end
  end

  describe :mirror_url do
    let(:gl_projects_create) do
      build_gitlab_projects('import-project', repo_name, test_repo_bundle)
    end
    let(:gl_mirror_create) do
      build_gitlab_projects('import-project', "#{repo_name}-mirror", test_repo_bundle)
    end

    it 'returns false for a non-mirrored repo' do
      (gl_project = gl_projects_create).exec
      subject.send(:mirror_url, gl_project.full_path).should be_false
    end

    it 'returns mirror url for a mirrored repo' do
      (gl_project = gl_projects_create).exec
      (gl_mirror = gl_mirror_create).exec
      add_mirror(gl_project.full_path, gl_mirror.full_path)
      subject.send(:mirror_url, gl_project.full_path).should == gl_mirror.full_path
    end
  end

  describe :show_ref do
    let(:gl_projects_create) do
      build_gitlab_projects('import-project', repo_name, test_repo_bundle)
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

  def add_mirror(repo_path, mirror_url)
    cmd = %W(git --git-dir=#{repo_path} remote add mirror #{mirror_url})
    system(*cmd)
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
