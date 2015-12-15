require_relative 'spec_helper'
require_relative '../../lib/gitlab_init'
require_relative '../mirror_shell'

describe PerforceSwarm::MirrorShell do
  before do
    FileUtils.mkdir_p(tmp_repos_path)
    GitlabConfig.any_instance.stub(repos_path: tmp_repos_path, audit_usernames: false)
    $logger = double('logger').as_null_object
    
    # Clear off any pre-existing args
    ARGV.clear
  end

  after do
    FileUtils.rm_rf(tmp_repos_path)
  end

  let(:tmp_repos_path) { File.join(ROOT_PATH, 'tmp', 'repositories') }
  let(:project_path) { 'namespace/project' }

  subject do
    PerforceSwarm::MirrorShell
  end

  describe :new do
    before do
      ARGV[0] = 'fetch'
    end

    context 'full path' do
      it 'should parse using the full path ending in .git' do
        ARGV[1] = File.join(tmp_repos_path, "#{project_path}.git")
        validate_project_path
      end

      it 'should parse using the full path without ending in .git' do
        ARGV[1] = File.join(tmp_repos_path, project_path)
        validate_project_path
      end
    end

    context 'namespace path' do
      it 'should parse using the namespace path ending in .git' do
        ARGV[1] = "#{project_path}.git"
        validate_project_path
      end

      it 'should parse using the namespace path without ending in .git' do
        ARGV[1] = project_path
        validate_project_path
      end
    end

    def validate_project_path
      shell = subject.new
      shell.command.should be == 'fetch'
      shell.project_name.should be == project_path
      shell.full_path.should be == File.join(tmp_repos_path, "#{project_path}.git")
    end
  end
end
