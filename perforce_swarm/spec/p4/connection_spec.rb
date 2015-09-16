require_relative '../spec_helper'
require_relative '../../p4/connection'
require_relative '../../git_fusion'

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
            'url'  => 'foo@unknown-host',
            'user' => 'p4test',
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

  describe :validate_config do
    it 'raises an exception when an invalid config is given' do
      [{},
       { 'enabled' => false },
       { 'enabled' => true },
       { 'enabled' => true, 'default' => {} },
       { 'enabled' => true, 'default' => { 'perforce' => { 'user' => 'perforce_user' } } }
      ].each do |config_hash|
        expect do
          PerforceSwarm::P4::Connection.validate_config(PerforceSwarm::GitFusion::Config.new(config_hash).entry)
        end.to raise_error(RuntimeError), config_hash.inspect
      end
    end

    it 'does not raise an exception when a valid config is given' do
      expect do
        PerforceSwarm::P4::Connection.validate_config(@p4config)
      end.to_not raise_error(RuntimeError), @p4config.inspect
    end
  end

  describe :connections do
    it 'is disconnected by default' do
      pending('P4::Connection tests require the p4d executable in your path.') if @p4d.empty?
      expect(@connection.connected?).to be_false
    end

    it 'we can connect to and disconnect from p4d' do
      pending('P4::Connection tests require the p4d executable in your path.') if @p4d.empty?
      @connection.connect
      sleep(0.5)
      expect(@connection.connected?).to be_true
      @connection.disconnect
      expect(@connection.connected?).to be_false
    end
  end

  describe :run do
    it 'allows us to run the info command without a client' do
      pending('P4::Connection tests require the p4d executable in your path.') if @p4d.empty?
      @connection.connect
      info = @connection.run('info')
      expect(info).to_not be_nil
      expect(info.first).to_not be_nil
      info = info.first
      expect(info['userName']).to eq('*unknown*')
      expect(info['serverRoot']).to eq(@p4root)
      @connection.disconnect
    end
    it 'allows us to create a user and run the users command without a client' do
      pending('P4::Connection tests require the p4d executable in your path.') if @p4d.empty?
      @connection.connect
      user_spec = {
          'User'    =>  'test-user',
          'Email'    => 'test-user@localhost',
          'FullName' => 'test-user'
      }
      @connection.input(user_spec).run('user', '-if')
      users = @connection.run('users')
      expect(users).to_not be_nil
      expect(users.length).to eq(2)
      expect(users[0]['User']).to eq('p4test')
      expect(users[1]['User']).to eq('test-user')
      @connection.disconnect
    end
    it 'allows us to list depots' do
      pending('P4::Connection tests require the p4d executable in your path.') if @p4d.empty?
      @connection.connect
      depots = @connection.run('depots')
      expect(depots.length).to eq(1)
      expect(depots[0]['name']).to eq('depot')
      expect(depots[0]['map']).to eq('depot/...')
      @connection.disconnect
    end
  end

  describe :with_temp_client do
    it 'creates a temporary client, with a temporary directory, and that the workspace is nuked when the block ends' do
      pending('P4::Connection tests require the p4d executable in your path.') if @p4d.empty?
      expect(@connection.connected?).to be_false
      client_name = ''
      client_root = ''

      @connection.with_temp_client do
        expect(@connection.client).to_not be_nil
        expect(@connection.client).to start_with('gitswarm-temp-')
        expect(@connection.connected?).to be_true
        # grab the client spec
        spec = @connection.run('client', '-o')
        spec = spec.first
        client_name = spec['Client']
        client_root = spec['Root']
        expect(Dir.exist?(client_root)).to be_true
      end
      expect(@connection.connected?).to be_false
      expect(Dir.exist?(client_root)).to be_false

      # re-connect to ensure that our client was nuked
      @connection.connect
      @connection.run('clients').each do |client|
        expect(client['client']).to_not eq(client_name)
      end
      @connection.disconnect
    end
  end

  describe :user do
    it 'raises an exception when the username is nil, false or the empty string' do
      [nil, false, ''].each do |user|
        expect { @connection.user(user) }.to raise_error(PerforceSwarm::P4::IdentityNotFound), @connection.inspect
      end
    end
  end

  describe :login do
    it 'raises an exception if an empty/nil or unknown user is given' do
      ['unknown-user', '', nil, false].each do |user|
        expect { @connection.user(user).login }.to raise_error(PerforceSwarm::P4::IdentityNotFound), @connection.inspect
      end
    end

    it 'raises an exception if nil or false is given for the password' do
      [nil, false].each do |password|
        expect do
          @connection.user('test-user').password(password).login
        end.to raise_error(PerforceSwarm::P4::LoginException), @connection.inspect
      end
    end

    it 'raises an exception if the wrong password is given' do
      create_user(@connection, 'test-user', 'test-password')
      ['wrongpass'].each do |password|
        expect do
          @connection.user('test-user').password(password).login
        end.to raise_error(PerforceSwarm::P4::CredentialInvalid), @connection.inspect
      end
    end

    it 'raises an exception if a user who has an empty password in perforce tries to login with a non-empty password' do
      create_user(@connection, 'test-user', '')
      ['wrongpass'].each do |password|
        expect do
          @connection.user('test-user').password(password).login
        end.to raise_error(PerforceSwarm::P4::CredentialInvalid), @connection.inspect
      end
    end

    it 'allows users with empty passwords to log in to Perforce with an empty password' do
      create_user(@connection, 'test-user', '')
      @connection.user('test-user').password('').login
    end

    it 'allows users to log in ' do
      create_user(@connection, 'test-user', '')
      create_user(@connection, 'another-test', 'withpassword')
      @connection.user('test-user').password('').login
      @connection.user('another-test').password('withpassword').login
    end
  end

  # helper functions
  def create_user(connection, user, password)
    connection.with_temp_client do
      user_spec             = connection.run('user', '-o', user)[0]
      user_spec['Password'] = password
      connection.input(user_spec).run('user', '-i', '-f')
    end
  end
end
