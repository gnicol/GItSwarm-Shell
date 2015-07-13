require 'json'
require_relative 'spec_helper'
require_relative '../git_fusion_repo'

describe PerforceSwarm::GitFusionRepo do
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

    it 'returns an empty list of repos when we get an empty description error from Git Fusion' do
      output = "Cloning into '@list'...\n" \
               "No option 'description' in section: '@repo'\n" \
               "fatal: Could not read from remote repository.\n\n" \
               'Please make sure you have the correct access rights' \
               'and the repository exists.'
      expect(PerforceSwarm::GitFusionRepo.parse_repos(output)).to eq({})
    end

    it 'returns a list of repos when they have descriptions' do
      from_examples_file('perforce_swarm/spec/examples/git_fusion_repo_valid.json')
    end
  end

  def from_examples_file(filename)
    JSON.parse(File.read(filename)).each do |example|
      expect(PerforceSwarm::GitFusionRepo.parse_repos(example[0])).to eq(example[1])
    end
  end
end
