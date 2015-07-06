require 'yaml'
require_relative 'spec_helper'
require_relative '../config'

describe PerforceSwarm::GitlabConfig do
  describe :git_fusion_config_block do
    let(:config) { PerforceSwarm::GitlabConfig.new }

    context 'with default and other blocks present' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
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
      it 'loads the default config block if one is present and no block id is specified' do
        expect(config.git_fusion_config_block['url']).to eq('foo@bar'), config.inspect
      end

      it 'loads the specified config block by id' do
        expect(config.git_fusion_config_block('foo')['url']).to eq('bar@baz'), config.inspect
      end

      it 'raises an exception if a specific block id is requested by not found' do
        expect { config.git_fusion_config_block('nonexistent') }.to raise_error(RuntimeError), config.inspect
      end
    end

    context 'no default block' do
      before do
        config.instance_variable_set(:@config, YAML.load(<<eos
git_fusion:
  foo:
    url: "bar@baz"
  bar:
    url: "baz@boop"
eos
                                                        )
                                    )
      end
      it 'loads the first configuration block given if the default is requested but not given' do
        expect(config.git_fusion_config_block(nil)['url']).to eq('bar@baz'), config.inspect
      end
    end

    context 'empty config' do
      before do
        config.instance_variable_set(:@config, git_fusion: {})
      end
      it 'raises an exception if no configuration is specified' do
        expect { config.git_fusion_config_block }.to raise_error(RuntimeError), config.inspect
      end
    end

    context 'nil config' do
      before do
        config.instance_variable_set(:@config, git_fusion: nil)
      end
      it 'raises an exception if the configuration is nil' do
        expect { config.git_fusion_config_block }.to raise_error(RuntimeError), config.inspect
      end
    end

    context 'invalid config' do
      before do
        config.instance_variable_set(:@config, git_fusion: 'one two three')
      end
      it 'raises an exception if an invalid configuration is given' do
        expect { config.git_fusion_config_block }.to raise_error(RuntimeError), config.inspect
      end
    end

    context 'no git_fusion block' do
      before do
        config.instance_variable_set(:@config, {})
      end
      it 'raises an exception if no git_fusion config block is found' do
        expect { config.git_fusion_config_block }.to raise_error(RuntimeError), config.inspect
      end
    end
  end
end
