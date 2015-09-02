require 'yaml'
require_relative 'spec_helper'
require_relative '../config'

describe PerforceSwarm::GitFusion::ConfigEntry do
  describe :[] do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'without global settings' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
  yoda:
    url: "http://foo@bar"
eos

                                             )
        )
      end
      it 'entries allow retrieval of config settings using Ruby hash syntax' do
        entry = config.git_fusion.entry
        expect(entry['url']).to eq('foo@bar'), entry.inspect
      end
    end

    context 'with global settings' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  global:
    user: global
    password: global-pass
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
  yoda:
    url: "http://foo@bar"
eos

                                             )
        )
      end
      it 'entries allow retrieval of config settings using Ruby hash syntax, with appropriate global values' do
        entry = config.git_fusion.entry
        expect(entry['url']).to eq('foo@bar')
        expect(entry['user']).to eq('global')
        expect(entry['password']).to eq('global-pass')
      end
    end
  end

  describe :[]= do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with global settings' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  global:
    user: global
    password: global-pass
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
  yoda:
    url: "http://foo@bar"
eos

                                             )
        )
      end
      it 'can set config values using Ruby hash syntax, with appropriate global values' do
        entry = config.git_fusion.entry
        expect(entry['url']).to eq('foo@bar')
        entry['url'] = 'http://foobar'
        expect(entry['url']).to eq('http://global@foobar')
        expect(entry['user']).to eq('global')
        expect(entry['password']).to eq('global-pass')
      end
      it 'can set config values using Ruby hash syntax that overrides global values' do
        entry = config.git_fusion.entry
        expect(entry['user']).to eq('global')
        entry['user'] = 'foo'
        expect(entry['url']).to eq('foo@bar')
        expect(entry['user']).to eq('foo')
        expect(entry['password']).to eq('global-pass')
      end
    end
  end

  describe :git_fusion_password do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with local, global and URL-based passwords' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  global:
    user: global
    password: global-pass
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
    password: "foopass"
  yoda:
    url: "http://foo:pass@bar"
eos

                                             )
        )
      end
      it 'returns the correct password values based on priority (entry, URL, global)' do
        entry = config.git_fusion.entry
        expect(entry.git_fusion_password).to eq('global-pass')
        entry = config.git_fusion.entry('foo')
        expect(entry.git_fusion_password).to eq('foopass')
        entry = config.git_fusion.entry('yoda')
        expect(entry.git_fusion_password).to eq('pass')
      end
      it 'returns the correct password values with Ruby hash syntax' do
        entry = config.git_fusion.entry
        expect(entry['password']).to eq('global-pass')
        entry = config.git_fusion.entry('foo')
        expect(entry['password']).to eq('foopass')
        entry = config.git_fusion.entry('yoda')
        expect(entry['password']).to eq('pass')
      end
    end
  end

  describe :expand_perforce_port do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with no perforce or global configuration' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
    password: "foopass"
  http_test:
    url: "http://foo:pass@bar"
eos
                                             )
        )
      end
      it 'leaves Perforce ports that contain a fqdn and port alone' do
        entry      = config.git_fusion.entry
        http_entry = config.git_fusion.entry('http_test')
        [nil,
         '',
         'hostname:1666',
         'host.com:1666',
         'non-standard-port.com:1667',
         '10.5.40.123:1666',
         '5.4.3.1:7661',
         'weird-123.host.name.org:123',
         'ssl:hostname:1666',
         'ssl:host.com:1666',
         'ssl:non-standard-port.com:1667',
         'ssl:10.5.40.123:1666',
         'ssl:5.4.3.1:7661',
         'ssl:weird-123.host.name.org:123'
        ].each do |example|
          expect(entry.expand_perforce_port(example)).to eq(example)
          expect(http_entry.expand_perforce_port(example)).to eq(example)
        end
      end
      it 'expands localhost-ish or missing fqdn Perforce ports to include GF host name' do
        entry      = config.git_fusion.entry
        http_entry = config.git_fusion.entry('http_test')
        { '1666'                           => 'bar:1666',
          '7767'                           => 'bar:7767',
          ':1666'                          => 'bar:1666',
          '127.0.0.1:1666'                 => 'bar:1666',
          '127.0.0.1:1667'                 => 'bar:1667',
          'localhost:1666'                 => 'bar:1666',
          'localhost.localdomain:1666'     => 'bar:1666',
          'localhost.localdom:1666'        => 'bar:1666',
          'ssl:1666'                       => 'ssl:bar:1666',
          'ssl:7767'                       => 'ssl:bar:7767',
          'ssl:127.0.0.1:1666'             => 'ssl:bar:1666',
          'ssl:127.0.0.1:1667'             => 'ssl:bar:1667',
          'ssl:localhost:1666'             => 'ssl:bar:1666',
          'ssl:localhost.localdomain:1666' => 'ssl:bar:1666',
          'ssl:localhost.localdom:1666'    => 'ssl:bar:1666'
        }.each do |example, expected|
          expect(entry.expand_perforce_port(example)).to eq(expected)
          expect(http_entry.expand_perforce_port(example)).to eq(expected)
        end
      end
    end
  end

  describe :perforce_password do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with no perforce or global configuration' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
    password: "foopass"
  yoda:
    url: "http://foo:pass@bar"
eos
                                             )
        )
      end
      it 'returns the correct perforce password based on priority' do
        entry = config.git_fusion.entry
        expect(entry.perforce_password).to eq('')
        entry = config.git_fusion.entry('foo')
        expect(entry.perforce_password).to eq('foopass')
      end
    end
    context 'with no perforce configuration' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  global:
    user: global
    password: global-pass
  default:
    url: "foo@bar"
  foo:
    url: "bar@baz"
    password: "foopass"
  yoda:
    url: "http://foo:pass@bar"
eos
                                             )
        )
      end
      it 'returns the correct perforce passwords based on priority' do
        entry = config.git_fusion.entry
        expect(entry.perforce_password).to eq('global-pass')
        entry = config.git_fusion.entry('foo')
        expect(entry.perforce_password).to eq('foopass')
      end
    end

    context 'with local and global perforce passwords' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  global:
    user: global
    password: global-pass
    perforce:
      user: global-perforce-user
      password: global-perforce-pass
  default:
    url: "foo@bar"
    perforce:
      user: perforce-user
      password: perforce-pass
  foo:
    url: "bar@baz"
    password: "foopass"
  yoda:
    url: "http://foo:pass@bar"
  skywalker:
    url: "http://foo@bar"
eos

                                             )
        )
      end
      it 'returns the correct perforce password values based on priority' do
        entry = config.git_fusion.entry
        expect(entry.perforce_password).to eq('perforce-pass')
        entry = config.git_fusion.entry('foo')
        expect(entry.perforce_password).to eq('global-perforce-pass')
        entry = config.git_fusion.entry('yoda')
        expect(entry.perforce_password).to eq('global-perforce-pass')
        entry = config.git_fusion.entry('skywalker')
        expect(entry.perforce_password).to eq('global-perforce-pass')
      end
    end
  end

  describe :perforce_user do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with no perforce or global configuration' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  default:
    url: "foo@bar"
  foo:
    url: "https://bar@baz"
    password: "foopass"
  yoda:
    user: yoda-user
    url: "http://foo:pass@bar"
eos
                                             )
        )
      end
      it 'returns the correct perforce user based on priority' do
        entry = config.git_fusion.entry
        expect(entry.perforce_user).to eq('gitswarm')
        entry = config.git_fusion.entry('foo')
        expect(entry.perforce_user).to eq('bar')
        entry = config.git_fusion.entry('yoda')
        expect(entry.perforce_user).to eq('yoda-user')
      end
    end
    context 'with no perforce configuration' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  global:
    user: global-user
    password: global-pass
  default:
    url: "foo@bar"
  foo:
    url: "http://baz"
    password: "foopass"
    user: "foo-user"
  yoda:
    url: "http://foo:pass@bar"
eos
                                             )
        )
      end
      it 'returns the correct perforce user based on priority' do
        entry = config.git_fusion.entry
        expect(entry.perforce_user).to eq('global-user')
        entry = config.git_fusion.entry('foo')
        expect(entry.perforce_user).to eq('foo-user')
        entry = config.git_fusion.entry('yoda')
        expect(entry.perforce_user).to eq('foo')
      end
    end

    context 'with local and global perforce passwords' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  some_value: some string
  global:
    user: global
    password: global-pass
    perforce:
      user: global-perforce-user
      password: global-perforce-pass
  default:
    url: "foo@bar"
    perforce:
      user: perforce-user
      password: perforce-pass
  bar:
    url: "http://somehost"
  foo:
    url: "http://baz"
    user: "foo-user"
    password: "foopass"
  yoda:
    url: "http://foo:pass@bar"
eos

                                             )
        )
      end
      it 'returns the correct perforce user values based on priority' do
        entry = config.git_fusion.entry
        expect(entry.perforce_user).to eq('perforce-user')
        entry = config.git_fusion.entry('bar')
        expect(entry.perforce_user).to eq('global-perforce-user')
        entry = config.git_fusion.entry('foo')
        expect(entry.perforce_user).to eq('global-perforce-user')
        entry = config.git_fusion.entry('yoda')
        expect(entry.perforce_user).to eq('global-perforce-user')
      end
    end
  end

  describe :auto_create_configured? do
    before do
      @base_config = PerforceSwarm::GitFusion::Config.new(
          'enabled' => true,
          'global' => {},
          'foo' => {
            'url'  => 'foo@unknown-host',
            'user' => 'p4test',
            'perforce' => {
              'port' => "rsh:#{@p4d} -r #{@p4root} -i -q"
            }
          }
      )
    end

    it 'returns false if auto_create is misconfigured or missing' do
      entry                = @base_config.entry
      entry['auto_create'] = { 'path_template' => 'path', 'repo_name_template' => 'name' }
      [nil,
       {},
       { 'foo' => 'bar' },
       { 'enabled' => true },
       { 'default' => { 'url' => 'foo@bar' } },
       @base_config.clone.entry,
       entry
      ].each do |config|
        entry                = @base_config.entry
        entry['auto_create'] = config
        expect(entry.auto_create_configured?).to be_false
      end
    end

    it 'returns false when the config has invalid values for auto_create path/repo_name templates' do
      [{ 'auto_create' => { 'path_template' => 0, 'repo_name_template' => '' } },
       { 'auto_create' => { 'path_template' => '', 'repo_name_template' => 'name' } },
       { 'auto_create' => { 'path_template' => 'path', 'repo_name_template' => 'name' } },
       { 'auto_create' => { 'path_template' => {}, 'repo_name_template' => 'name' } },
       { 'auto_create' => { 'path_template' => '//some/path/{project-path}', 'repo_name_template' => 'name' } },
       { 'auto_create' => { 'path_template' => '//some/path/{project-path}', 'repo_name_template' => ['name'] } },
       { 'auto_create' => { 'path_template' => '//static/path', 'repo_name_template' => 'name' } },
       { 'auto_create' => { 'path_template' => '//some/{namespace}/{project-path}', 'repo_name_template' => 'name' } },
       { 'auto_create' => { 'path_template' => '//some/{namespace}/{project-path}', 'repo_name_template' => ['nom'] } },
       { 'auto_create' => { 'path_template' => '//static/path', 'repo_name_template' => 'name' } }
      ].each do |config|
        entry                = @base_config.entry
        entry['auto_create'] = config
        expect(entry.auto_create_configured?).to be_false
      end
    end

    it 'returns true when the config is valid' do
      config = @base_config.clone.entry
      config['auto_create'] = { 'path_template' => '//gitswarm/{namespace}/{project-path}',
                                'repo_name_template' => 'gitswarm-{namespace}-{project-path}' }
      expect(config.auto_create_configured?).to be_true
      config['auto_create'] = { 'path_template' => '//gitswarm/{namespace}/{project-path}',
                                'repo_name_template' => '{namespace}.{project-path}' }
      expect(config.auto_create_configured?).to be_true
    end
  end
end
