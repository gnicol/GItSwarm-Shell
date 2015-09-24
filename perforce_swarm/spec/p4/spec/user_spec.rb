require_relative '../../spec_helper'
require_relative '../../../p4/connection'
require_relative '../../../p4/spec/user'
require_relative '../../../git_fusion'

describe PerforceSwarm::P4::Spec::User do
  test_user = 'test-user'
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
    it 'creates a user with no extra parameters' do
      output = PerforceSwarm::P4::Spec::User.create(@connection, test_user).last
      user_spec = @connection.run(%W(user -o #{test_user})).last
      expect(output.match("User #{test_user} saved")).to be_true
      expect(user_spec['User'].eql?(test_user)).to be_true
      expect(user_spec['Type'].eql?('standard')).to be_true
    end

    it 'creates a user with extra parameters' do
      output = PerforceSwarm::P4::Spec::User.create(@connection,
                                                    test_user,
                                                    'Password' => 'bar').last
      user_spec = @connection.run(%W(user -o #{test_user})).last
      expect(output.match("User #{test_user} saved")).to be_true
      expect(user_spec['User'].eql?(test_user)).to be_true
      expect(user_spec['Type'].eql?('standard')).to be_true
      expect(user_spec['Password'].eql?('******')).to be_true
    end

    it 'creates a user with extra parameters and overrides' do
      output = PerforceSwarm::P4::Spec::User.create(@connection,
                                                    test_user,
                                                    'Password' => 'bar', 'Email' => 'x@y.com').last
      user_spec = @connection.run(%W(user -o #{test_user})).last
      expect(output.match("User #{test_user} saved")).to be_true
      expect(user_spec['User'].eql?(test_user)).to be_true
      expect(user_spec['Type'].eql?('standard')).to be_true
      expect(user_spec['Password'].eql?('******')).to be_true
      expect(user_spec['Email'].eql?('x@y.com')).to be_true
    end

    it 'fails to create a user with extra invalid parameters' do
      expect do
        PerforceSwarm::P4::Spec::User.create(
                  @connection,
                  test_user,
                  'Password' => 'bar', 'foo' => 'bar').to raise_error(P4Exception)
      end
    end
  end

  describe :privilege do
    it 'adds a privilege to protections' do
      output = PerforceSwarm::P4::Spec::User.add_privilege(@connection, test_user, 'super', '//...').last
      expect(output.match('Protections saved')).to be_true
      protections = @connection.run(*%w(protect -o)).last
      expect(protections['Protections'].last.eql?("super user #{test_user} * //...")).to be_true
    end

    it 'fails to add a privilege with a bad permission' do
      expect do
        PerforceSwarm::P4::Spec::User.add_privilege(
                  @connection,
                  test_user,
                  'superdooper',
                  '//...').to raise_error(P4Exception)
      end
    end
  end

  describe :password do
    it 'sets a password for a user' do
      PerforceSwarm::P4::Spec::User.create(@connection, test_user)
      output = PerforceSwarm::P4::Spec::User.set_password(@connection, test_user, '1234').last
      expect(output.match('Password updated')).to be_true
    end

    it 'fails to set a password when the user does not exist' do
      expect do
        PerforceSwarm::P4::Spec::User.set_password(@connection, 'duff user', '1234').to raise_error(P4Exception)
      end
    end
  end
end
