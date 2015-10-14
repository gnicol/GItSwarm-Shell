require_relative '../../spec_helper'
require_relative '../../../p4/connection'
require_relative '../../../p4/spec/client'
require_relative '../../../git_fusion'

describe PerforceSwarm::P4::Spec::Client do
  test_client = 'test_client'
  p4_client_util = PerforceSwarm::P4::Spec::Client
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

  describe :client do
    it 'creates a client with no extra parameters' do
      client_spec = p4_client_util.create(@connection, test_client)
      expect(client_spec).to_not be_nil
      expect(client_spec['Client'].eql?(test_client)).to be_true
    end

    it 'creates a client with extra parameters' do
      client_spec = p4_client_util.create(@connection, test_client,
                                          'Root' => '/root', 'View' => ["//depot/... //#{test_client}/extra"])
      puts "Client spec #{client_spec}"
      expect(client_spec).to_not be_nil
      expect(client_spec['Client'].eql?(test_client)).to be_true
      expect(client_spec['Root'].eql?('/root')).to be_true
      expect(client_spec['View'].eql?(["//depot/... //#{test_client}/extra"])).to be_true
    end

    it 'fails to create a client with extra invalid parameters' do
      expect do
        p4_client_util.create(
                  @connection,
                  test_client,
                  'Root' => '/root', 'foo' => 'bar').to raise_error(P4Exception)
      end
    end

    it 'is possible to get a client after save' do
      p4_client_util.save(@connection, p4_client_util.create(@connection, test_client))
      expect(p4_client_util.get_client(@connection, test_client)).to_not be_nil
    end

    it 'is possible to get a default client' do
      expect(p4_client_util.get_client(@connection)).to_not be_nil
    end

    it 'is possible to get a client after save temp when still connected' do
      p4_client_util.save(@connection, p4_client_util.create(@connection, test_client), true)
      expect(p4_client_util.get_client(@connection, test_client)).to_not be_nil
    end

    it 'saves a client and can report its existence' do
      p4_client_util.save(@connection, p4_client_util.create(@connection, test_client))
      expect(p4_client_util.exists?(@connection, test_client)).to be_true
    end

    it 'returns false for a client that does not exist' do
      expect(p4_client_util.exists?(@connection, 'dummy')).to be_false
    end
  end
end
