require_relative 'spec_helper'
require_relative '../../lib/gitlab_shell'
require_relative '../../lib/gitlab_access_status'

describe GitlabShell do
  before do
    FileUtils.mkdir_p(tmp_repos_path)
  end

  after do
    FileUtils.rm_rf(tmp_repos_path)
  end

  subject do
    ARGV[0] = key_id
    PerforceSwarm::Mirror.tap do |mirror|
      mirror.stub(fetch: true)
    end
    GitlabShell.new(key_id).tap do |shell|
      shell.stub(exec_cmd: :exec_called)
      shell.stub(api: api)
    end
  end

  let(:api) do
    double(GitlabNet).tap do |api|
      api.stub(discover: { 'name' => 'John Doe' })
      api.stub(check_access: GitAccessStatus.new(true))
    end
  end

  let(:key_id) { "key-#{rand(100) + 100}" }
  let(:ssh_cmd) { nil }
  let(:tmp_repos_path) { File.join(ROOT_PATH, 'tmp', 'repositories') }

  before do
    GitlabConfig.any_instance.stub(repos_path: tmp_repos_path, audit_usernames: false)
  end

  describe :exec do
    context 'git-upload-pack' do
      let(:ssh_cmd) { 'git-upload-pack gitlab-ci.git' }
      after { subject.exec(ssh_cmd) }

      it 'should execute the command', override: true do
        subject.should_receive(:exec_cmd).with('git-upload-pack', File.join(tmp_repos_path, 'gitlab-ci.git'))
      end

      it 'should log the command execution', override: true do
        message = 'gitlab-shell: executing git command '
        message << "<git-upload-pack #{File.join(tmp_repos_path, 'gitlab-ci.git')}> "
        message << "for user with key #{key_id}."
        $logger.should_receive(:info).with(message)
      end

      it 'should use usernames if configured to do so', override: true do
        GitlabConfig.any_instance.stub(audit_usernames: true)
        $logger.should_receive(:info) { |msg| msg.should =~ /for John Doe/ }
      end
    end

    context 'git-receive-pack' do
      let(:ssh_cmd) { 'git-receive-pack gitlab-ci.git' }
      after { subject.exec(ssh_cmd) }

      it 'should execute the command', override: true do
        subject.should_receive(:exec_cmd).with('git-receive-pack', File.join(tmp_repos_path, 'gitlab-ci.git'))
      end

      it 'should log the command execution', override: true do
        message = 'gitlab-shell: executing git command '
        message << "<git-receive-pack #{File.join(tmp_repos_path, 'gitlab-ci.git')}> "
        message << "for user with key #{key_id}."
        $logger.should_receive(:info).with(message)
      end
    end

    describe 'git-annex', override: true do
      let(:ssh_cmd) { 'git-annex-shell commit /~/gitlab-ci.git SHA256' }

      before do
        GitlabConfig.any_instance.stub(git_annex_enabled?: true)
      end

      after { subject.exec(ssh_cmd) }

      it 'should execute the command' do
        subject.should_receive(:exec_cmd)
          .with('git-annex-shell', 'commit', File.join(tmp_repos_path, 'gitlab-ci.git'), 'SHA256')
      end
    end
  end

  describe :validate_access, override: true do
    let(:ssh_cmd) { 'git-upload-pack gitlab-ci.git' }
    after { subject.exec(ssh_cmd) }

    it 'should call api.check_access' do
      api.should_receive(:check_access)
        .with('git-upload-pack', 'gitlab-ci.git', key_id, '_any')
    end

    it 'should disallow access and log the attempt if check_access returns false status' do
      api.stub(check_access: GitAccessStatus.new(false))
      message = 'gitlab-shell: Access denied for git command <git-upload-pack gitlab-ci.git> '
      message << "by user with key #{key_id}."
      $logger.should_receive(:warn).with(message)
    end
  end
end
