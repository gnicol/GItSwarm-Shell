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
end
