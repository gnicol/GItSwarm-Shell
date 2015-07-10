require 'json'
require_relative 'spec_helper'
require_relative '../repo'

describe PerforceSwarm::Repo do
  before do
    FileUtils.mkdir_p(tmp_repos_path)
    GitlabConfig.any_instance.stub(repos_path: tmp_repos_path)
    PerforceSwarm::GitlabConfig.any_instance.stub(git_fusion: tmp_git_fusion_config)
  end

  after do
    FileUtils.rm_rf(tmp_repos_path)
  end

  let(:tmp_repos_path) { File.join(ROOT_PATH, 'tmp', 'repositories') }
  let(:test_repo_bundle) { File.join(ROOT_PATH, 'perforce_swarm', 'spec', '6-branch-4-tag-repo.bundle') }
  let(:repo_name) { 'gitswarm.git' }
  let(:tmp_git_fusion_config) do
    {
      'default' => {
        'url'   => 'http://example.com',
        'user'  => 'gitswarm'
      }
    }
  end

  subject do
    PerforceSwarm::Repo
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
      subject.new(gl_project.full_path).send(:mirror_url).should be_false
      subject.new(gl_project.full_path).send(:mirrored?).should be_false
    end

    it 'returns mirror url for a mirrored repo' do
      (gl_project = gl_projects_create).exec
      (gl_mirror = gl_mirror_create).exec
      add_mirror(gl_project.full_path, gl_mirror.full_path)
      subject.new(gl_project.full_path).send(:mirror_url).should be == gl_mirror.full_path
      subject.new(gl_project.full_path).send(:mirrored?).should be_true
    end

    it 'can set a mirror remote on a non-mirrored repo' do
      (gl_project = gl_projects_create).exec
      url = 'http://example.com/Talkhouse'
      subject.new(gl_project.full_path).send(:mirror_url=, url).should be == url
      subject.new(gl_project.full_path).send(:mirror_url).should be == url
      subject.new(gl_project.full_path).send(:mirrored?).should be_true
    end

    it 'blows up for an invalid instance given via mirror://instance/repo format' do
      (gl_project = gl_projects_create).exec
      url         = 'mirror://not-a-thing/Talkhouse'
      expect { subject.new(gl_project.full_path).send(:mirror_url=, url) }
        .to raise_error(RuntimeError, /not found or is missing a URL\./)
    end

    it 'can set a mirror remote using mirror://instance/repo format' do
      (gl_project = gl_projects_create).exec
      url         = 'mirror://default/Talkhouse'
      resolved    = 'http://example.com/Talkhouse'
      subject.new(gl_project.full_path).send(:mirror_url=, url).should be == url
      subject.new(gl_project.full_path).send(:mirror_url).should be == resolved
      subject.new(gl_project.full_path).send(:mirrored?).should be_true
    end

    it 'can set a mirror remote on an already-mirrored repo' do
      (gl_project = gl_projects_create).exec
      url1 = 'http://example.com/Talkhouse'
      url2 = 'http://example2.com/TalkhouseB'
      subject.new(gl_project.full_path).send(:mirror_url=, url1).should be == url1
      subject.new(gl_project.full_path).send(:mirror_url).should be == url1
      subject.new(gl_project.full_path).send(:mirrored?).should be_true
      subject.new(gl_project.full_path).send(:mirror_url=, url2).should be == url2
      subject.new(gl_project.full_path).send(:mirror_url).should be == url2
      subject.new(gl_project.full_path).send(:mirrored?).should be_true
    end
  end
end
