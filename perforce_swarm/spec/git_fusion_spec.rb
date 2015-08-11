require_relative 'spec_helper'
require_relative '../git_fusion'

describe PerforceSwarm::GitFusion do
  valid_urls = %w(git@127.0.0.1
                  git@localhost
                  user@10.0.0.2
                  user@host-name.com
                  dashed-user@host-name.com
                  user@localhost/repo
                  git@host.com/
                  git@host.com/repo.git
                  git@host.com:@status
                  git@host.com:@status@repo
                  git@host.com:@wait@talkhouse@12
                  git@5.4.3.2:@wait@talkhouse@12
                  ssh://127.0.0.1
                  ssh://127.0.0.1:8080
                  ssh://host.com/
                  ssh://host.com:1234/
                  ssh://host.com/repo.git
                  ssh://host.com/@status
                  ssh://host.com/@status@repo
                  ssh://host.com/@wait@talkhouse@12
                  ssh://10.0.0.2/@wait@talkhouse@12
                  ssh://localhost:443/repo
                  ssh://10.9.9.2:999/goober
                  ssh://user@localhost
                  ssh://user@localhost/@list
                  ssh://user@127.0.0.1/@list
                  ssh://user:pass@localhost/@list
                  ssh://user:pass@9.8.7.6/@list
                  ssh://user@9.9.9.9:1234/@list
                  ssh://user@localhost:1234/@list
                  ssh://user:pass@localhost:1234/@list
                  ssh://user:password@localhost
                  ssh://user:password@localhost:1233
                  ssh://user:password@localhost/repo
                  ssh://user:password@localhost/
                  ssh://user:password@localhost:1233
                  http://127.0.0.1
                  https://127.0.0.1
                  http://127.0.0.1:8080
                  http://host.com/
                  https://host.com/
                  http://host.com:1234/
                  https://host.com:4321/
                  http://host.com/repo.git
                  http://host.com/@status
                  http://host.com/@status@repo
                  http://host.com/@wait@talkhouse@12
                  http://10.0.0.2/@wait@talkhouse@12
                  https://host.com/repo.git
                  https://host.com/@status
                  https://host.com/@status@repo
                  https://host.com/@wait@talkhouse@12
                  https://123.23.23.23:443
                  https://localhost:443/repo
                  http://10.9.9.2:999/goober
                  http://user@localhost
                  https://user@localhost
                  http://user@localhost/@list
                  http://user@127.0.0.1/@list
                  https://user@localhost/@list
                  http://user:pass@localhost/@list
                  http://user:pass@9.8.7.6/@list
                  https://user:pass@localhost/@list
                  http://user@localhost:1234/@list
                  http://user@9.9.9.9:1234/@list
                  https://user@localhost:1234/@list
                  http://user:pass@localhost:1234/@list
                  https://user:pass@localhost:1234/@list
                  http://user:password@localhost
                  http://user:password@localhost:1233
                  http://user:password@localhost/repo
                  https://user:password@localhost
                  https://user:password@localhost:1233
                  https://user:password@localhost/repo)
  invalid_urls = %w(darth-vader
                    host.foo:/path
                    /local/file/path
                    relative/path
                    ~/another/path
                    file://path/foo
                    rsync://host.com/path)
  valid_repo_tests = { 'git@127.0.0.1/repo' => 'repo',
                       'user@localhost/differentrepo' => 'differentrepo',
                       'git@localhost:ssh-repo' => 'ssh-repo',
                       'git@localhost:@wait@ssh-repo@12' => 'ssh-repo',
                       'git@localhost:@wait@ssh-repo.git@12' => 'ssh-repo.git',
                       'git@localhost:@status@ssh-repo' => 'ssh-repo',
                       'ssh://127.0.0.1/repo' => 'repo',
                       'ssh://user@localhost/differentrepo' => 'differentrepo',
                       'ssh://localhost:22/ssh-repo' => 'ssh-repo',
                       'ssh://localhost:22/' => nil,
                       'ssh://localhost:22' => nil,
                       'ssh://localhost/@wait@ssh-repo@12' => 'ssh-repo',
                       'ssh://localhost/@status@ssh-repo' => 'ssh-repo',
                       'http://127.0.0.1/repo' => 'repo',
                       'http://user@localhost/differentrepo' => 'differentrepo',
                       'http://localhost:22/ssh-repo' => 'ssh-repo',
                       'http://localhost:22/' => nil,
                       'http://localhost:22' => nil,
                       'http://localhost/@wait@ssh-repo@12' => 'ssh-repo',
                       'http://localhost/@status@ssh-repo' => 'ssh-repo',
                       'https://127.0.0.1/repo' => 'repo',
                       'https://user@localhost/differentrepo' => 'differentrepo',
                       'https://localhost:22/ssh-repo' => 'ssh-repo',
                       'https://localhost:22/' => nil,
                       'https://localhost:22' => nil,
                       'https://localhost/@wait@ssh-repo@12' => 'ssh-repo',
                       'https://localhost/@status@ssh-repo' => 'ssh-repo'
  }
  exceptions = { 'https://123.23.23.23:443' => 'https://123.23.23.23',
                 'https://localhost:443/repo' => 'https://localhost/repo'
  }
  let(:config) { PerforceSwarm::GitlabConfig.new }
  describe :valid_url? do
    it 'returns true on valid git fusion urls' do
      valid_urls.each do |url|
        expect(PerforceSwarm::GitFusion::URL.valid?(url)).to be_true, url
      end
    end

    it 'returns false on invalid git fusion urls' do
      invalid_urls.each do |url|
        expect(PerforceSwarm::GitFusion::URL.valid?(url)).to be_false, url
      end
      expect(PerforceSwarm::GitFusion::URL.valid?('')).to be_false
      expect(PerforceSwarm::GitFusion::URL.valid?(nil)).to be_false
      expect(PerforceSwarm::GitFusion::URL.valid?(false)).to be_false
    end
  end

  describe :valid_command? do
    it 'returns true for valid commands' do
      %w(help info list status wait).each do |command|
        expect(PerforceSwarm::GitFusion::URL.valid_command?(command)).to be_true, command
      end
    end

    it 'returns false for invalid commands' do
      ['sit', 'down', 'stay', 'play dead', '!list', '!*!**', '@list', '', nil, false].each do |command|
        expect(PerforceSwarm::GitFusion::URL.valid_command?(command)).to be_false, command.inspect
      end
    end

    it 'raises an exception for invalid commands specified in a url' do
      ['sit', 'down', 'stay', 'play dead', '!list', '!*!**', '@list'].each do |command|
        expect do
          PerforceSwarm::GitFusion::URL.new("user@host:@#{command}")
        end.to raise_error(RuntimeError), command.inspect

        expect do
          PerforceSwarm::GitFusion::URL.new("user@host:@#{command}@repoid")
        end.to raise_error(RuntimeError), command.inspect
      end
    end
  end

  describe :clear_path do
    it 'deletes the current command, repo and extra settings' do
      valid_urls.each do |url|
        to_test = PerforceSwarm::GitFusion::URL.new(url)
        to_test.clear_path
        expect(to_test.command).to be_false
        expect(to_test.repo).to be_false
        expect(to_test.extra).to be_false
      end
    end
  end

  describe :clear_command do
    it 'deletes the current command and extra settings' do
      valid_repo_tests.each do |url, repo|
        to_test = PerforceSwarm::GitFusion::URL.new(url)
        to_test.clear_command
        expect(to_test.command).to be_false
        expect(to_test.extra).to be_false
        expect(to_test.repo).to eq(repo)
      end
    end
  end

  describe :repo do
    it 'returns the repo for git fusion urls containing a repo, nil if they don\'t' do
      valid_repo_tests.each do |url, repo|
        to_test = PerforceSwarm::GitFusion::URL.new(url)
        expect(to_test.repo).to eq(repo), "#{url} => #{repo} GOT " + to_test.repo.to_s
      end
    end

    it 'can be called multiple times and still give expected results' do
      valid_repo_tests.each do |url, repo|
        to_test = PerforceSwarm::GitFusion::URL.new('user@host')
        to_test.parse(url)
        expect(to_test.repo).to eq(repo), "#{url} => #{repo} GOT " + to_test.repo.to_s
      end
    end

    it 'overrides the initial repo setting with a new one if it is a string' do
      examples = [%w(git@localhost:repo new-repo),
                  %w(git@127.0.0.1:repo new-repo),
                  %w(git@localhost:@status@repo new-repo),
                  %w(git@127.0.0.1:@status@repo new-repo),
                  %w(git@localhost:@status@repo@12 new-repo),
                  %w(git@127.0.0.1:@status@repo@12 new-repo)
                 ]
      examples.each do |example|
        url, new_repo = example
        to_test = PerforceSwarm::GitFusion::URL.new(url)
        to_test.repo = new_repo
        expect(to_test.repo).to eq(new_repo)
      end
    end
  end

  describe :parse do
    it 'strips passwords from the URL by default' do
      valid_urls.each do |url|
        output   = PerforceSwarm::GitFusion::URL.new(url)
        expected = exceptions[url] || url.gsub(/\/$|:pass(word)?/, '')
        expect(output.strip_password(true).to_s).to eq(expected),
                                                    "#{url if url != expected} '#{expected}' => '#{output}'"
      end
    end
  end

  describe :url do
    expected = { 'git@127.0.0.1/repo' => 'git@127.0.0.1',
                 'user@localhost/differentrepo' => 'user@localhost',
                 'git@localhost:ssh-repo' => 'git@localhost',
                 'git@localhost:@wait@ssh-repo@12' => 'git@localhost',
                 'git@localhost:@wait@ssh-repo.git@12' => 'git@localhost',
                 'git@localhost:@status@ssh-repo' => 'git@localhost',
                 'ssh://127.0.0.1/repo' => 'ssh://127.0.0.1',
                 'ssh://user@localhost/differentrepo' => 'ssh://user@localhost',
                 'ssh://localhost:22/ssh-repo' => 'ssh://localhost:22',
                 'ssh://localhost:22/' => 'ssh://localhost:22',
                 'ssh://localhost:22' => 'ssh://localhost:22',
                 'ssh://localhost/@wait@ssh-repo@12' => 'ssh://localhost',
                 'ssh://localhost/@status@ssh-repo' => 'ssh://localhost',
                 'http://127.0.0.1/repo' => 'http://127.0.0.1',
                 'http://user@localhost/differentrepo' => 'http://user@localhost',
                 'http://localhost:22/ssh-repo' => 'http://localhost:22',
                 'http://localhost:22/' => 'http://localhost:22',
                 'http://localhost:22' => 'http://localhost:22',
                 'http://localhost/@wait@ssh-repo@12' => 'http://localhost',
                 'http://localhost/@status@ssh-repo' => 'http://localhost',
                 'https://127.0.0.1/repo' => 'https://127.0.0.1',
                 'https://user@localhost/differentrepo' => 'https://user@localhost',
                 'https://localhost:22/ssh-repo' => 'https://localhost:22',
                 'https://localhost:22/' => 'https://localhost:22',
                 'https://localhost:22' => 'https://localhost:22',
                 'https://localhost/@wait@ssh-repo@12' => 'https://localhost',
                 'https://localhost/@status@ssh-repo' => 'https://localhost'
    }
    it 'returns the scheme, user, password and host portions of the URL only' do
      expected.each do |url, repoless|
        to_test = PerforceSwarm::GitFusion::URL.new(url)
        expect(to_test.url).to eq(repoless), to_test.url + " => #{repoless}"
      end
    end

    it 'can be called multiple times and produce expected results' do
      expected.each do |url, repoless|
        to_test = PerforceSwarm::GitFusion::URL.new('user@host')
        to_test.parse(url)
        expect(to_test.url).to eq(repoless), to_test.url + " => #{repoless}"
      end
    end
  end

  describe :to_s do
    it 'extends a base URL with the Git Fusion extended command syntax' do
      # [url, command, repo, extra]
      expected = { ['git@127.0.0.1', 'list', false, false] => 'git@127.0.0.1:@list',
                   ['git@127.0.0.1/repo', 'list', false, false] => 'git@127.0.0.1/@list',
                   ['git@127.0.0.1/repo', 'status', false, false] => 'git@127.0.0.1/@status',
                   ['git@127.0.0.1/repo', 'wait', true, false] => 'git@127.0.0.1/@wait@repo',
                   ['git@127.0.0.1/repo-name', 'wait', true, false] => 'git@127.0.0.1/@wait@repo-name',
                   ['git@127.0.0.1/repo', 'wait', true, 12] => 'git@127.0.0.1/@wait@repo@12',
                   ['git@127.0.0.1/repo', 'status', true, '0123456789'] => 'git@127.0.0.1/@status@repo@0123456789',
                   ['git@localhost', 'list', false, false] => 'git@localhost:@list',
                   ['git@localhost/repo', 'list', false, false] => 'git@localhost/@list',
                   ['git@localhost/repo', 'status', false, false] => 'git@localhost/@status',
                   ['git@localhost/repo', 'wait', true, false] => 'git@localhost/@wait@repo',
                   ['git@localhost/repo-name', 'wait', true, false] => 'git@localhost/@wait@repo-name',
                   ['git@localhost/repo', 'wait', true, 12] => 'git@localhost/@wait@repo@12',
                   ['git@localhost/repo', 'status', true, '0123456789'] => 'git@localhost/@status@repo@0123456789',
                   ['git@127.0.0.1', 'list', false, false] => 'git@127.0.0.1:@list',
                   ['git@127.0.0.1:repo', 'list', false, false] => 'git@127.0.0.1:@list',
                   ['git@127.0.0.1:repo', 'status', false, false] => 'git@127.0.0.1:@status',
                   ['git@127.0.0.1:repo', 'wait', true, false] => 'git@127.0.0.1:@wait@repo',
                   ['git@127.0.0.1:repo-name', 'wait', true, false] => 'git@127.0.0.1:@wait@repo-name',
                   ['git@127.0.0.1:repo', 'wait', true, 12] => 'git@127.0.0.1:@wait@repo@12',
                   ['git@127.0.0.1:repo', 'status', true, '0123456789'] => 'git@127.0.0.1:@status@repo@0123456789',
                   ['git@localhost', 'list', false, false] => 'git@localhost:@list',
                   ['git@localhost:repo', 'list', false, false] => 'git@localhost:@list',
                   ['git@localhost:repo', 'status', false, false] => 'git@localhost:@status',
                   ['git@localhost:repo', 'wait', true, false] => 'git@localhost:@wait@repo',
                   ['git@localhost:repo-name', 'wait', true, false] => 'git@localhost:@wait@repo-name',
                   ['git@localhost:repo', 'wait', true, 12] => 'git@localhost:@wait@repo@12',
                   ['git@localhost:repo', 'status', true, '0123456789'] => 'git@localhost:@status@repo@0123456789',
                   ['http://127.0.0.1', 'list', false, false] => 'http://127.0.0.1/@list',
                   ['http://127.0.0.1/repo', 'list', false, false] => 'http://127.0.0.1/@list',
                   ['http://127.0.0.1/repo', 'status', false, false] => 'http://127.0.0.1/@status',
                   ['http://127.0.0.1/repo', 'wait', true, false] => 'http://127.0.0.1/@wait@repo',
                   ['http://127.0.0.1/repo-name', 'wait', true, false] => 'http://127.0.0.1/@wait@repo-name',
                   ['http://127.0.0.1/repo', 'wait', true, 12] => 'http://127.0.0.1/@wait@repo@12',
                   ['http://127.0.0.1/repo', 'status', true, '0123456789'] =>
                      'http://127.0.0.1/@status@repo@0123456789',
                   ['http://localhost', 'list', false, false] => 'http://localhost/@list',
                   ['http://localhost/repo', 'list', false, false] => 'http://localhost/@list',
                   ['http://localhost/repo', 'status', false, false] => 'http://localhost/@status',
                   ['http://localhost/repo', 'wait', true, false] => 'http://localhost/@wait@repo',
                   ['http://localhost/repo-name', 'wait', true, false] => 'http://localhost/@wait@repo-name',
                   ['http://localhost/repo', 'wait', true, 12] => 'http://localhost/@wait@repo@12',
                   ['http://localhost/repo', 'status', true, '0123456789'] =>
                      'http://localhost/@status@repo@0123456789',
                   ['https://127.0.0.1/repo', 'status', true, '0123456789'] =>
                      'https://127.0.0.1/@status@repo@0123456789',
                   ['https://localhost', 'list', false, false] => 'https://localhost/@list',
                   ['ssh://localhost', 'list', false, false] => 'ssh://localhost/@list',
                   ['ssh://localhost/repo', 'list', false, false] => 'ssh://localhost/@list',
                   ['ssh://localhost/repo', 'status', false, false] => 'ssh://localhost/@status',
                   ['ssh://localhost/repo', 'wait', true, false] => 'ssh://localhost/@wait@repo',
                   ['ssh://localhost/repo-name', 'wait', true, false] => 'ssh://localhost/@wait@repo-name',
                   ['ssh://localhost/repo', 'wait', true, 12] => 'ssh://localhost/@wait@repo@12',
                   ['ssh://localhost/repo', 'status', true, '0123456789'] =>
                      'ssh://localhost/@status@repo@0123456789',
                   ['ssh://127.0.0.1/repo', 'status', true, '0123456789'] =>
                      'ssh://127.0.0.1/@status@repo@0123456789',
                   ['ssh://localhost', 'list', false, false] => 'ssh://localhost/@list',
                   ['http://127.0.0.1:8080', 'list', false, false] => 'http://127.0.0.1:8080/@list',
                   ['http://127.0.0.1:8080/repo', 'list', false, false] => 'http://127.0.0.1:8080/@list',
                   ['http://127.0.0.1:8080/repo', 'status', false, false] => 'http://127.0.0.1:8080/@status',
                   ['http://127.0.0.1:8080/repo', 'wait', true, false] => 'http://127.0.0.1:8080/@wait@repo',
                   ['http://127.0.0.1:8080/repo-name', 'wait', true, false] => 'http://127.0.0.1:8080/@wait@repo-name',
                   ['http://127.0.0.1:8080/repo', 'wait', true, 12] => 'http://127.0.0.1:8080/@wait@repo@12',
                   ['http://127.0.0.1:8080/repo', 'status', true, '0123456789'] =>
                      'http://127.0.0.1:8080/@status@repo@0123456789',
                   ['http://localhost:8080', 'list', false, false] => 'http://localhost:8080/@list',
                   ['http://localhost:8080/repo', 'list', false, false] => 'http://localhost:8080/@list',
                   ['http://localhost:8080/repo', 'status', false, false] => 'http://localhost:8080/@status',
                   ['http://localhost:8080/repo', 'wait', true, false] => 'http://localhost:8080/@wait@repo',
                   ['http://localhost:8080/repo-name', 'wait', true, false] => 'http://localhost:8080/@wait@repo-name',
                   ['http://localhost:8080/repo', 'wait', true, 12] => 'http://localhost:8080/@wait@repo@12',
                   ['http://localhost:8080/repo', 'status', true, '0123456789'] =>
                      'http://localhost:8080/@status@repo@0123456789',
                   ['https://127.0.0.1:8080/repo', 'status', true, '0123456789'] =>
                      'https://127.0.0.1:8080/@status@repo@0123456789',
                   ['https://localhost:8080', 'list', false, false] => 'https://localhost:8080/@list',
                   ['http://foo@127.0.0.1:8080', 'list', false, false] => 'http://foo@127.0.0.1:8080/@list',
                   ['http://foo@127.0.0.1:8080/repo', 'list', false, false] => 'http://foo@127.0.0.1:8080/@list',
                   ['http://foo@127.0.0.1:8080/repo', 'status', false, false] => 'http://foo@127.0.0.1:8080/@status',
                   ['http://foo@127.0.0.1:8080/repo', 'wait', true, false] => 'http://foo@127.0.0.1:8080/@wait@repo',
                   ['http://foo@127.0.0.1:8080/repo-name', 'wait', true, false] => 'http://foo@127.0.0.1:8080/@wait@repo-name',
                   ['http://foo@127.0.0.1:8080/repo', 'wait', true, 12] => 'http://foo@127.0.0.1:8080/@wait@repo@12',
                   ['http://foo@127.0.0.1:8080/repo', 'status', true, '0123456789'] =>
                      'http://foo@127.0.0.1:8080/@status@repo@0123456789',
                   ['http://foo@localhost:8080', 'list', false, false] => 'http://foo@localhost:8080/@list',
                   ['http://foo@localhost:8080/repo', 'list', false, false] => 'http://foo@localhost:8080/@list',
                   ['http://foo@localhost:8080/repo', 'status', false, false] => 'http://foo@localhost:8080/@status',
                   ['http://foo@localhost:8080/repo', 'wait', true, false] => 'http://foo@localhost:8080/@wait@repo',
                   ['http://foo@localhost:8080/repo-name', 'wait', true, false] => 'http://foo@localhost:8080/@wait@repo-name',
                   ['http://foo@localhost:8080/repo', 'wait', true, 12] => 'http://foo@localhost:8080/@wait@repo@12',
                   ['http://foo@localhost:8080/repo', 'status', true, '0123456789'] =>
                      'http://foo@localhost:8080/@status@repo@0123456789',
                   ['https://foo@127.0.0.1:8080/repo', 'status', true, '0123456789'] =>
                      'https://foo@127.0.0.1:8080/@status@repo@0123456789',
                   ['https://foo@localhost:8080', 'list', false, false] => 'https://foo@localhost:8080/@list',
                   ['http://foo:pass@127.0.0.1:8080', 'list', false, false] => 'http://foo@127.0.0.1:8080/@list',
                   ['http://foo:pass@127.0.0.1:8080/repo', 'list', false, false] => 'http://foo@127.0.0.1:8080/@list',
                   ['http://foo:pass@127.0.0.1:8080/repo', 'status', false, false] => 'http://foo@127.0.0.1:8080/@status',
                   ['http://foo:pass@127.0.0.1:8080/repo', 'wait', true, false] => 'http://foo@127.0.0.1:8080/@wait@repo',
                   ['http://foo:pass@127.0.0.1:8080/repo-name', 'wait', true, false] => 'http://foo@127.0.0.1:8080/@wait@repo-name',
                   ['http://foo:pass@127.0.0.1:8080/repo', 'wait', true, 12] => 'http://foo@127.0.0.1:8080/@wait@repo@12',
                   ['http://foo:pass@127.0.0.1:8080/repo', 'status', true, '0123456789'] =>
                      'http://foo@127.0.0.1:8080/@status@repo@0123456789',
                   ['http://foo:pass@localhost:8080', 'list', false, false] => 'http://foo@localhost:8080/@list',
                   ['http://foo:pass@localhost:8080/repo', 'list', false, false] => 'http://foo@localhost:8080/@list',
                   ['http://foo:pass@localhost:8080/repo', 'status', false, false] => 'http://foo@localhost:8080/@status',
                   ['http://foo:pass@localhost:8080/repo', 'wait', true, false] => 'http://foo@localhost:8080/@wait@repo',
                   ['http://foo:pass@localhost:8080/repo-name', 'wait', true, false] => 'http://foo@localhost:8080/@wait@repo-name',
                   ['http://foo:pass@localhost:8080/repo', 'wait', true, 12] => 'http://foo@localhost:8080/@wait@repo@12',
                   ['http://foo:pass@localhost:8080/repo', 'status', true, '0123456789'] =>
                      'http://foo@localhost:8080/@status@repo@0123456789',
                   ['https://foo@127.0.0.1:8080/repo', 'status', true, '0123456789'] =>
                      'https://foo@127.0.0.1:8080/@status@repo@0123456789',
                   ['https://foo:pass@localhost:8080', 'list', false, false] => 'https://foo@localhost:8080/@list',
                   ['ssh://localhost:8080', 'list', false, false] => 'ssh://localhost:8080/@list',
                   ['ssh://localhost:8080/repo', 'list', false, false] => 'ssh://localhost:8080/@list',
                   ['ssh://localhost:8080/repo', 'status', false, false] => 'ssh://localhost:8080/@status',
                   ['ssh://localhost:8080/repo', 'wait', true, false] => 'ssh://localhost:8080/@wait@repo',
                   ['ssh://localhost:8080/repo-name', 'wait', true, false] => 'ssh://localhost:8080/@wait@repo-name',
                   ['ssh://localhost:8080/repo', 'wait', true, 12] => 'ssh://localhost:8080/@wait@repo@12',
                   ['ssh://localhost:8080/repo', 'status', true, '0123456789'] =>
                      'ssh://localhost:8080/@status@repo@0123456789',
                   ['ssh://127.0.0.1:8080/repo', 'status', true, '0123456789'] =>
                      'ssh://127.0.0.1:8080/@status@repo@0123456789',
                   ['ssh://localhost:8080', 'list', false, false] => 'ssh://localhost:8080/@list'
      }
      expected.each do |args, result|
        url, command, repo, extra = args
        parsed = PerforceSwarm::GitFusion::URL.new(url)
        parsed.command = command
        parsed.repo = repo
        parsed.extra = extra
        expect(parsed.to_s).to eq(result), parsed.to_s + ' GIVEN ' + args.inspect + " EXPECTED #{result}"
      end
    end

    it 'does not mutate URLs unless you ask nicely' do
      valid_urls.each do |url|
        output   = PerforceSwarm::GitFusion::URL.new(url)
        expected = exceptions[url] || url.gsub(/\/$|:pass(word)?/, '')
        expect(output.to_s).to eq(expected), "#{url if url != expected} #{expected} => #{output}"
      end
    end

    it 'does not strip the password from the URL if strip_password is false' do
      valid_urls.each do |url|
        output   = PerforceSwarm::GitFusion::URL.new(url)
        expected = exceptions[url] || url.gsub(/\/$/, '')
        expect(output.strip_password(false).to_s)
          .to eq(expected), "#{url if url != expected} '#{expected}' => '#{output}'"
      end
    end

    it 'can be called several times and produce expected results' do
      valid_urls.each do |url|
        output     = PerforceSwarm::GitFusion::URL.new('user@host')
        output.parse(url)
        expected   = exceptions[url] || url.gsub(/\/$|:pass(word)?/, '')
        expect(output.to_s).to eq(expected), "#{url if url != expected} #{expected} => #{output}"
      end
    end

    it 'raises an exception if an extra parameter is given with no command or repo present' do
      to_test       = PerforceSwarm::GitFusion::URL.new('git@localhost')
      to_test.extra = 'foo'
      expect { to_test.to_s }.to raise_error(RuntimeError)
    end

    it 'raises an exception when trying to instantiate a URL object with an invalid base URL' do
      invalid_urls.each do |url|
        expect { PerforceSwarm::GitFusion::URL.new(url) }.to raise_error(Exception), url
      end
    end

    it 'raises an exception when trying to extend with an invalid or unknown command' do
      to_test = PerforceSwarm::GitFusion::URL.new('git@localhost')
      expect { to_test.command = '' }.to raise_error(RuntimeError)
      expect { to_test.command = 'sit' }.to raise_error(RuntimeError)
      expect { to_test.command = 'learn kung fu' }.to raise_error(RuntimeError)
    end

    it 'raises an exception when a repo is expected but not present' do
      urls = %w(git@127.0.0.1
                git@localhost
                http://127.0.0.1
                http://localhost
                https://127.0.0.1
                https://localhost
                http://127.0.0.1:8080
                http://localhost:8080
                https://127.0.0.1:8080
                https://localhost:8080
                http://127.0.0.1/
                http://localhost/
                https://127.0.0.1/
                https://localhost/
                http://127.0.0.1:8080/
                http://localhost:8080/
                https://127.0.0.1:8080/
                https://localhost:8080/
                http://user@127.0.0.1/
                http://user@localhost/
                https://user@127.0.0.1/
                https://user@localhost/
                http://user:pass@127.0.0.1/
                http://user:pass@localhost/
                https://user:pass@127.0.0.1/
                https://user:pass@localhost/
                ssh://git@127.0.0.1
                ssh://git@localhost
                ssh://127.0.0.1
                ssh://localhost
                ssh://127.0.0.1:1234
                ssh://localhost:1234)
      urls.each do |url|
        parsed = PerforceSwarm::GitFusion::URL.new(url)
        parsed.command = 'list'
        expect { parsed.repo = true }.to raise_error(RuntimeError), url
      end
    end
  end

  describe :version_check do
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
      it 'returns valid data and not outdated if version 2015.2' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.2/1128995 (2015/06/23)')
        current_config = PerforceSwarm::GitlabConfig.new.git_fusion
        git_fusion.validate_entries('2015.2').each do | instance, values |
          expect(values[:valid]).to be_true
          expect(values[:config]['url']).to eq(current_config[instance]['url'])
          expect(values[:version]).to eq('2015.2.1128995')
          expect(values[:outdated]).to be_false
        end
      end

      it 'returns non-valid and outdated if version < 2015.2' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.1/142456 (2015/05/21)')
        git_fusion.validate_entries('2015.2').each do | _instance, values |
          expect(values[:valid]).to be_false
          expect(values[:version]).to eq('2015.1.142456')
          expect(values[:outdated]).to be_true
        end
      end

      it 'returns non-valid and outdated if we specified patch version' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.1/121 (2015/05/21)')
        git_fusion.validate_entries('2015.2.122').each do | _instance, values |
          expect(values[:valid]).to be_false
          expect(values[:version]).to eq('2015.1.121')
          expect(values[:outdated]).to be_true
        end
      end

      it 'fails if version specified is not valid' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_return('Rev. Git Fusion/2015.1/121 (2015/05/21)')
        expect { git_fusion.validate_entries('A2015/2/122') }
          .to raise_error(RuntimeError, 'Invalid min_version specified: A2015/2/122')
      end

      it 'returns error message caught from git command execution' do
        git_fusion = PerforceSwarm::GitFusion
        git_fusion.stub(:run).and_raise(PerforceSwarm::GitFusion::RunError, 'Very generic git error.')
        git_fusion.validate_entries('2015.2').each do | _instance, values |
          expect(values[:valid]).to be_false
          expect(values[:error]).to eq('Very generic git error.')
        end
      end
    end
  end
end
