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
end
