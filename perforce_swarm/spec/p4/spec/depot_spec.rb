require_relative '../../spec_helper'
require_relative '../../../p4/connection'
require_relative '../../../p4/spec/depot'
require_relative '../../../git_fusion'

describe PerforceSwarm::P4::Spec::Depot do
  test_depot = 'test-depot'
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

  it 'creates a depot with no extra parameters' do
    output = PerforceSwarm::P4::Spec::Depot.create(@connection, test_depot).last
    expect(output.match("Depot #{test_depot} saved")).to be_true
    depot_spec = @connection.run(%W(depot -o #{test_depot})).last
    expect(depot_spec['Depot'].eql?(test_depot)).to be_true
  end

  it 'creates a depot with extra parameters including overrides' do
    # Set Type = 'spec' with extra parameter 'Suffix'. 'Suffix' will pass but be ignored for the
    # default type of local (does not matter about the order)
    output = PerforceSwarm::P4::Spec::Depot.create(@connection, test_depot, 'Suffix' => 'yy', 'Type' => 'spec').last
    expect(output.match("Depot #{test_depot} saved")).to be_true
    depot_spec = @connection.run(%W(depot -o #{test_depot})).last
    expect(depot_spec['Depot'].eql?(test_depot)).to be_true
    expect(depot_spec['Suffix'].eql?('yy')).to be_true
    expect(depot_spec['Type'].eql?('spec')).to be_true
  end

  it 'fails to create a depot with invalid extra parameters' do
    expect do
      PerforceSwarm::P4::Spec::Depot.create(@connection, test_depot, 'xxx' => 'yyy').to raise_exception(P4Exception)
    end
  end

  it 'returns false for an unknown depot in exists' do
    expect(PerforceSwarm::P4::Spec::Depot.exists?(@connection, test_depot)).to be_false
  end

  it 'returns true for an existing depot' do
    output = PerforceSwarm::P4::Spec::Depot.create(@connection, test_depot).last
    expect(output.match("Depot #{test_depot} saved")).to be_true
    expect(PerforceSwarm::P4::Spec::Depot.exists?(@connection, test_depot)).to be_true
  end

  describe :all do
    it 'returns an empty list if no depots exist' do
      @connection.run(%w(depot -d -f depot)).last.inspect
      depots = PerforceSwarm::P4::Spec::Depot.all(@connection)
      expect(depots).to be_a(Hash)
      expect(depots.empty?).to be_true
    end

    it 'returns a list of depots keyed on name' do
      PerforceSwarm::P4::Spec::Depot.create(@connection, 'depot1')
      PerforceSwarm::P4::Spec::Depot.create(@connection, 'depot2', 'Type' => 'remote')
      PerforceSwarm::P4::Spec::Depot.create(@connection, 'stream', 'Type' => 'stream')
      depots = PerforceSwarm::P4::Spec::Depot.all(@connection)
      expect(depots).to be_a(Hash)
      expect(depots['depot1'].nil?).to be_false
      expect(depots['depot2'].nil?).to be_false
      expect(depots['stream'].nil?).to be_false
      expect(depots['depot3'].nil?).to be_true
      expect(depots['stream']['type']).to eq('stream')
    end
  end

  describe :id_from_path do
    it 'extracts the correct depot name/ID from the given path' do
      depot_spec = PerforceSwarm::P4::Spec::Depot
      { '//.git-fusion/foo/bar'          => '.git-fusion',
        '//gitswarm/blah/blah'           => 'gitswarm',
        '//depot/with/trailing/dots/...' => 'depot',
        '//depot'                        => 'depot',
        'invalid/depot/path'             => nil
      }.each do |path, id|
        expect(depot_spec.id_from_path(path)).to eq(id)
      end
    end

    describe :fetch do
      it 'returns nil for an unknown depot id' do
        expect(PerforceSwarm::P4::Spec::Depot.fetch(@connection, test_depot)).to be_nil
      end

      context 'with existing depot' do
        it 'returns a hash with the proper depot name' do
          output = PerforceSwarm::P4::Spec::Depot.create(@connection, test_depot).last
          expect(output.match("Depot #{test_depot} saved")).to be_true
          expect(PerforceSwarm::P4::Spec::Depot.fetch(@connection, test_depot)['Depot']).to eq(test_depot)
        end

        it 'defaults to a streams depth of 1' do
          output = PerforceSwarm::P4::Spec::Depot.create(@connection, test_depot, 'Type' => 'stream').last
          expect(output.match("Depot #{test_depot} saved")).to be_true
          expect(PerforceSwarm::P4::Spec::Depot.fetch(@connection, test_depot)['numericStreamDepth']).to eq(1)
        end
      end
    end
  end
end
