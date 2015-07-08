require 'json'
require_relative 'spec_helper'
require_relative '../repo'

describe PerforceSwarm::Repo do
  before do
    FileUtils.mkdir_p(tmp_repos_path)
    GitlabConfig.any_instance.stub(repos_path: tmp_repos_path)
  end

  after do
    FileUtils.rm_rf(tmp_repos_path)
  end

  let(:tmp_repos_path) { File.join(ROOT_PATH, 'tmp', 'repositories') }
  let(:test_repo_bundle) { File.join(ROOT_PATH, 'perforce_swarm', 'spec', '6-branch-4-tag-repo.bundle') }
  let(:repo_name) { 'gitswarm.git' }

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
  end
end
