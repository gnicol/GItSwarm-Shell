require_relative 'spec_helper'
require_relative '../git_fusion_repo'

describe PerforceSwarm::GitFusionRepo do
  describe :git_fusion_url? do
    valid_urls   = %w(git@127.0.0.1 git@127.0.0.1:8222 git@localhost git@localhost:8377 user@10.0.0.2
                   user@host-name.com dashed-user@host-name.com:999)
    invalid_urls = %w('' http://127.0.0.1 https://127.0.0.1 ssh://127.0.0.1 inval!d@127.0.0.1 darth-vader
                   luke-skywalker@* git@127.0.0.1/path git@localhost:22/path/2 host.foo:/path /local/file/path
                   relative/path ~/another/path file://path/foo rsync://host.com/path)
    it 'returns true on valid git fusion urls' do
      valid_urls.each do |url|
        expect(PerforceSwarm::GitFusionRepo.git_fusion_url?(url)).to be_true
      end
    end

    it 'returns false on invalid git fusion urls' do
      invalid_urls.each do |url|
        expect(PerforceSwarm::GitFusionRepo.git_fusion_url?(url)).to be_false
      end
      expect(PerforceSwarm::GitFusionRepo.git_fusion_url?(nil)).to be_false
    end
  end

  describe :parse_repos do
    it 'returns an empty list with empty input' do
      expect(PerforceSwarm::GitFusionRepo.parse_repos('')).to eq({})
    end

    it 'return an empty list with nil input' do
      expect(PerforceSwarm::GitFusionRepo.parse_repos(nil)).to eq({})
    end

    it 'returns an empty list when no repos are present in the input' do
      expect(PerforceSwarm::GitFusionRepo.parse_repos('')).to eq({})
    end

    it 'returns an empty list with invalid input' do
      JSON.parse(File.read('perforce_swarm/spec/examples/git_fusion_repo_invalid.json')).each do |invalid_example|
        expect(PerforceSwarm::GitFusionRepo.parse_repos(invalid_example)).to eq({})
      end
    end

    it 'returns a list of repos when they have empty descriptions' do
      output = "Cloning into '@list'...\n" +
               "No option 'description' in section: '@repo'\n" +
               "fatal: Could not read from remote repository.\n\n" +
               "Please make sure you have the correct access rights" +
               "and the repository exists."
      expect(PerforceSwarm::GitFusionRepo.parse_repos(output)).to eq({})
    end

    it 'returns a list of repos when they have descriptions' do
      from_examples_file('perforce_swarm/spec/examples/git_fusion_repo_with_descriptions.json')
    end
  end

  def from_examples_file(filename)
    JSON.parse(File.read(filename)).each do |example|
      expect(PerforceSwarm::GitFusionRepo.parse_repos(example[0])).to eq(example[1])
    end
  end

end
