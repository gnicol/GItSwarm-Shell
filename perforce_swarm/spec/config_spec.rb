require 'yaml'
require_relative 'spec_helper'
require_relative '../config'

describe PerforceSwarm::GitlabConfig do
  describe :git_fusion_entry do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with default and other entries present' do
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
      it 'loads the default config entry if one is present and no entry id is specified' do
        expect(config.git_fusion_entry['url']).to eq('foo@bar'), config.inspect
      end

      it 'loads the specified config entry by id' do
        expect(config.git_fusion_entry('foo')['url']).to eq('bar@baz'), config.inspect
      end

      it 'handles non-hash config entries' do
        expect(config.git_fusion['enabled']).to be_true, config.inspect
        expect(config.git_fusion['some_value']).to eq('some string'), config.inspect
      end

      it 'raises an exception if a specific entry id is requested by not found' do
        expect { config.git_fusion_entry('nonexistent') }.to raise_error(RuntimeError), config.inspect
      end
    end

    context 'no default entry' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  foo:
    url: "bar@baz"
  bar:
    url: "baz@boop"
eos
                                                        )
                                    )
      end
      it 'loads the first configuration entry as the default one' do
        expect(config.git_fusion_entry(nil)['url']).to eq('bar@baz'), config.inspect
      end
    end

    context 'empty config' do
      before do
        config.instance_variable_set(:@config, git_fusion: {})
      end
      it 'raises an exception if no configuration is specified' do
        expect { config.git_fusion_entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'nil config' do
      before do
        config.instance_variable_set(:@config, git_fusion: nil)
      end
      it 'raises an exception if the configuration is nil' do
        expect { config.git_fusion_entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'invalid config' do
      before do
        config.instance_variable_set(:@config, git_fusion: 'one two three')
      end
      it 'raises an exception if an invalid configuration is given' do
        expect { config.git_fusion_entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'entry contains no URL' do
      before do
        config.instance_variable_set(:@config, git_fusion: { foo: 'bar' })
      end
      it 'raises an exception if a config entry does not at least have a URL' do
        expect { config.git_fusion_entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'no git_fusion entry' do
      before do
        config.instance_variable_set(:@config, {})
      end
      it 'raises an exception if no git_fusion config entry is found' do
        expect { config.git_fusion_entry }.to raise_error(RuntimeError), config.inspect
      end
      it 'defaults to disabled' do
        expect(config.git_fusion['enabled']).to be_false, config.inspect
      end
    end

    context 'with global block' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  enabled: true
  global:
    user: global-user
    password: global-password
    url: http://global-url
  foo:
    url: "bar@baz"
  bar:
    url: "baz@boop"
  luke:
    url: luke@tatooine
    user: luke
  vader:
    url: darth@thedeathstar
    user: darth
    password: thedarkside
  no-url:
    user: username
eos
                                             )
        )
      end
      it 'uses global settings when there are no entry-specific ones (default entry)' do
        entry = config.git_fusion_entry
        expect(entry['user']).to eq('global-user'), entry.pretty_inspect
        expect(entry['password']).to eq('global-password'), entry.pretty_inspect
        expect(entry['url']).to eq('bar@baz'), entry.pretty_inspect
      end
      it 'uses global settings when there are no entry-specific ones (specific entry)' do
        entry = config.git_fusion_entry('bar')
        expect(entry['user']).to eq('global-user'), entry.pretty_inspect
        expect(entry['password']).to eq('global-password'), entry.pretty_inspect
        expect(entry['url']).to eq('baz@boop'), entry.pretty_inspect
      end
      it 'uses specific settings when specified, even when globals exist' do
        entry = config.git_fusion_entry('vader')
        expect(entry['user']).to eq('darth'), entry.pretty_inspect
        expect(entry['password']).to eq('thedarkside'), entry.pretty_inspect
        expect(entry['url']).to eq('darth@thedeathstar'), entry.pretty_inspect
      end
      it 'uses entry-specific settings first, and globals when specific ones are not present' do
        entry = config.git_fusion_entry('luke')
        expect(entry['user']).to eq('luke'), entry.pretty_inspect
        expect(entry['password']).to eq('global-password'), entry.pretty_inspect
        expect(entry['url']).to eq('luke@tatooine'), entry.pretty_inspect
      end
      it 'returns nil for config parameters that are requested but do not exist' do
        entry = config.git_fusion_entry('luke')
        expect(entry['foo']).to be_nil, entry.pretty_inspect
      end
      it 'does not consider "global" to be a valid entry' do
        expect { config.git_fusion_entry('global') }.to raise_error(RuntimeError), config.inspect
      end
      it 'still considers entries with no URL to be invalid' do
        expect { config.git_fusion_entry('no-url') }.to raise_error(RuntimeError), config.inspect
      end
    end
  end
end
