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
        entry = config.git_fusion_entry
        expect(entry['url']).to eq('foo@bar')
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
        entry = config.git_fusion_entry
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
        entry = config.git_fusion_entry
        expect(entry['url']).to eq('foo@bar')
        entry['url'] = 'http://foobar'
        expect(entry['url']).to eq('http://foobar')
        expect(entry['user']).to eq('global')
        expect(entry['password']).to eq('global-pass')
      end
      it 'can set config values using Ruby hash syntax that overrides global values' do
        entry = config.git_fusion_entry
        expect(entry['user']).to eq('global')
        entry['user'] = 'foo'
        expect(entry['url']).to eq('foo@bar')
        expect(entry['user']).to eq('foo')
        expect(entry['password']).to eq('global-pass')
      end
    end
  end
end
