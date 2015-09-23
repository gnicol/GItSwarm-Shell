require_relative '../../spec_helper'
require_relative '../../../p4/connection'
require_relative '../../../p4/spec/user'
require_relative '../../../git_fusion'

describe PerforceSwarm::P4::Connection do
  # ensure we can even run the tests by looking for p4d executable
  before(:all) do
    @p4d = `PATH=$PATH:/opt/perforce/sbin which p4d`.strip
  end

  # setup and teardown of temporary p4root directory
  before(:each) do
    @p4root   = Dir.mktmpdir
    @p4config = PerforceSwarm::GitFusion::Config.new(
      'enabled' => true,
      'default' => {
        'url'   => 'foo@unknown-host',
        'user'  => 'p4test',
        'perforce' => {
          'port' => "rsh:#{@p4d} -r #{@p4root} -i -q"
        }
      }
    ).entry
    @connection = PerforceSwarm::P4::Connection.new(@p4config, @p4root)
  end

  after(:each) do
    @connection.disconnect if @connection
    FileUtils.remove_entry_secure @p4root
  end

  describe :user do
    test_user = 'test-user'
    it 'creates a user' do
      output = PerforceSwarm::P4::Spec::User.create(@connection, test_user).last
      user_spec = @connection.run('user', '-o', test_user).last
      expect(output.match("User #{test_user} saved")).to be_true
      expect(user_spec['User'].eql?(test_user)).to be_true
      expect(user_spec['Type'].eql?('standard')).to be_true
    end

    it 'creates a user with extra parameters' do
      output = PerforceSwarm::P4::Spec::User.create(@connection,
                                                    test_user,
                                                    'Password' => 'bar').last
      user_spec = @connection.run('user', '-o', test_user).last
      expect(output.match("User #{test_user} saved")).to be_true
      expect(user_spec['User'].eql?(test_user)).to be_true
      expect(user_spec['Type'].eql?('standard')).to be_true
      expect(user_spec['Password'].eql?('******')).to be_true
    end

    it 'fails to create a user with extra invalid parameters' do
      expect do
        PerforceSwarm::P4::Spec::User.create(
                  @connection,
                  test_user,
                  'Password' => 'bar', 'foo' => 'bar').last.to raise_error(P4Exception)
      end
    end
  end
end
