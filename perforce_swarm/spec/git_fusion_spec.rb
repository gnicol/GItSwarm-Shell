require_relative 'spec_helper'
require_relative '../git_fusion'

describe PerforceSwarm::GitFusion do
  valid_urls = %w(git@127.0.0.1 git@127.0.0.1:8222 git@localhost git@localhost:8377 user@10.0.0.2
                  user@host-name.com dashed-user@host-name.com:999 http://127.0.0.1 https://127.0.0.1
                  http://127.0.0.1:8080 https://123.23.23.23:443 user@localhost/repo user@localhost:1233/repo
                  https://localhost:443/repo http://10.9.9.2:999/goober http://user:password@localhost
                  http://user:password@localhost:1233 http://user:password@localhost/repo
                  https://user:password@localhost https://user:password@localhost:1233
                  https://user:password@localhost/repo)
  invalid_urls = %w('' ssh://127.0.0.1 inval!d@127.0.0.1 darth-vader
                    luke-skywalker@* host.foo:/path /local/file/path
                    relative/path ~/another/path file://path/foo rsync://host.com/path)

  describe :valid_url? do
    it 'returns true on valid git fusion urls' do
      valid_urls.each do |url|
        expect(PerforceSwarm::GitFusion.valid_url?(url)).to be_true
      end
    end

    it 'returns false on invalid git fusion urls' do
      invalid_urls.each do |url|
        expect(PerforceSwarm::GitFusion.valid_url?(url)).to be_false
      end
      expect(PerforceSwarm::GitFusion.valid_url?(nil)).to be_false
    end
  end

  describe :valid_command? do
    it 'returns true for valid commands' do
      %w(help info list status wait).each do |command|
        expect(PerforceSwarm::GitFusion.valid_command?(command)).to be_true
      end
    end

    it 'returns false for invalid commands' do
      ['sit', 'down', 'stay', 'play dead', '!list', '!*!**', '@list', nil, ''].each do |command|
        expect(PerforceSwarm::GitFusion.valid_command?(command)).to be_false
      end
    end
  end

  describe :repo do
    it 'returns the repo for git fusion urls containing a repo, nil if they don\'t' do
      expected = { 'git@127.0.0.1/repo' => 'repo',
                   'user@localhost/differentrepo' => 'differentrepo',
                   'git@localhost:22/ssh-repo' => 'ssh-repo',
                   'git@localhost:22/' => nil,
                   'git@localhost:22' => nil,
                   'http://127.0.0.1/repo' => 'repo',
                   'http://user@localhost/differentrepo' => 'differentrepo',
                   'http://localhost:22/ssh-repo' => 'ssh-repo',
                   'http://localhost:22/' => nil,
                   'http://localhost:22' => nil,
                   'https://127.0.0.1/repo' => 'repo',
                   'https://user@localhost/differentrepo' => 'differentrepo',
                   'https://localhost:22/ssh-repo' => 'ssh-repo',
                   'https://localhost:22/' => nil,
                   'https://localhost:22' => nil
      }
      expected.each do |url, repo|
        expect(PerforceSwarm::GitFusion.repo(url)).to eq(repo)
      end
    end
  end

  describe :remove_repo do
    it 'can remove the repo for git fusion urls containing a repo' do
      expected = { 'git@127.0.0.1/repo' => 'git@127.0.0.1',
                   'user@localhost/differentrepo' => 'user@localhost',
                   'git@localhost:22/ssh-repo' => 'git@localhost:22',
                   'git@localhost:22/' => 'git@localhost:22',
                   'git@localhost:22' => 'git@localhost:22',
                   'http://127.0.0.1/repo' => 'http://127.0.0.1',
                   'http://user@localhost/differentrepo' => 'http://user@localhost',
                   'http://user:password@localhost/differentrepo' => 'http://user:password@localhost',
                   'http://localhost:22/ssh-repo' => 'http://localhost:22',
                   'http://localhost:22/' => 'http://localhost:22',
                   'http://localhost:22' => 'http://localhost:22',
                   'https://127.0.0.1/repo' => 'https://127.0.0.1',
                   'https://user@localhost/differentrepo' => 'https://user@localhost',
                   'https://localhost:22/ssh-repo' => 'https://localhost:22',
                   'https://localhost:22/' => 'https://localhost:22',
                   'https://localhost:22' => 'https://localhost:22'
      }
      expected.each do |url, repoless|
        expect(PerforceSwarm::GitFusion.remove_repo(url)).to eq(repoless)
      end
    end
  end

  describe :extend_url do
    it 'extends a base URL with the Git Fusion extended command syntax' do
      # [url, command, repo, extra]
      expected = { ['git@127.0.0.1', 'list', false, false] => 'git@127.0.0.1:@list',
                   ['git@127.0.0.1/repo', 'list', false, false] => 'git@127.0.0.1:@list',
                   ['git@127.0.0.1/repo', 'status', false, false] => 'git@127.0.0.1:@status',
                   ['git@127.0.0.1/repo', 'wait', true, false] => 'git@127.0.0.1:@wait@repo',
                   ['git@127.0.0.1/repo-name', 'wait', true, false] => 'git@127.0.0.1:@wait@repo-name',
                   ['git@127.0.0.1/repo', 'wait', true, 12] => 'git@127.0.0.1:@wait@repo@12',
                   ['git@127.0.0.1/repo', 'status', true, '0123456789ABCDEF'] =>
                       'git@127.0.0.1:@status@repo@0123456789ABCDEF',
                   ['git@localhost', 'list', false, false] => 'git@localhost:@list',
                   ['git@localhost/repo', 'list', false, false] => 'git@localhost:@list',
                   ['git@localhost/repo', 'status', false, false] => 'git@localhost:@status',
                   ['git@localhost/repo', 'wait', true, false] => 'git@localhost:@wait@repo',
                   ['git@localhost/repo-name', 'wait', true, false] => 'git@localhost:@wait@repo-name',
                   ['git@localhost/repo', 'wait', true, 12] => 'git@localhost:@wait@repo@12',
                   ['git@localhost/repo', 'status', true, '0123456789ABCDEF'] =>
                       'git@localhost:@status@repo@0123456789ABCDEF',
                   ['http://127.0.0.1', 'list', false, false] => 'http://127.0.0.1:@list',
                   ['http://127.0.0.1/repo', 'list', false, false] => 'http://127.0.0.1:@list',
                   ['http://127.0.0.1/repo', 'status', false, false] => 'http://127.0.0.1:@status',
                   ['http://127.0.0.1/repo', 'wait', true, false] => 'http://127.0.0.1:@wait@repo',
                   ['http://127.0.0.1/repo-name', 'wait', true, false] => 'http://127.0.0.1:@wait@repo-name',
                   ['http://127.0.0.1/repo', 'wait', true, 12] => 'http://127.0.0.1:@wait@repo@12',
                   ['http://127.0.0.1/repo', 'status', true, '0123456789ABCDEF'] =>
                       'http://127.0.0.1:@status@repo@0123456789ABCDEF',
                   ['http://localhost', 'list', false, false] => 'http://localhost:@list',
                   ['http://localhost/repo', 'list', false, false] => 'http://localhost:@list',
                   ['http://localhost/repo', 'status', false, false] => 'http://localhost:@status',
                   ['http://localhost/repo', 'wait', true, false] => 'http://localhost:@wait@repo',
                   ['http://localhost/repo-name', 'wait', true, false] => 'http://localhost:@wait@repo-name',
                   ['http://localhost/repo', 'wait', true, 12] => 'http://localhost:@wait@repo@12',
                   ['http://localhost/repo', 'status', true, '0123456789ABCDEF'] =>
                       'http://localhost:@status@repo@0123456789ABCDEF',
                   ['https://127.0.0.1/repo', 'status', true, '0123456789ABCDEF'] =>
                       'https://127.0.0.1:@status@repo@0123456789ABCDEF',
                   ['https://localhost', 'list', false, false] => 'https://localhost:@list'
      }
      expected.each do |args, result|
        args = args.map { |arg| arg.to_s if arg }
        expect(PerforceSwarm::GitFusion.extend_url(*args)).to eq(result)
      end
    end

    it 'raises an exception when trying to extend an invalid URL' do
      invalid_urls.each do |url|
        expect { PerforceSwarm::GitFusion.extend_url(url, 'list') }.to raise_error(RuntimeError)
      end
    end

    it 'raises an exception when trying to extend with an invalid or unknown command' do
      original = 'git@localhost'
      expect { PerforceSwarm::GitFusion.extend_url(original, nil) }.to raise_error(RuntimeError)
      expect { PerforceSwarm::GitFusion.extend_url(original, '') }.to raise_error(RuntimeError)
      expect { PerforceSwarm::GitFusion.extend_url(original, 'sit') }.to raise_error(RuntimeError)
      expect { PerforceSwarm::GitFusion.extend_url(original, 'learn kung fu') }.to raise_error(RuntimeError)
    end

    it 'raises an exception when extending a URL and a repo is expected but not present' do
      # [url, command, repo, extra]
      invalid_args = [['git@127.0.0.1', 'list', true, false],
                      ['git@localhost', 'list', true, false],
                      ['http://127.0.0.1', 'list', true, false],
                      ['http://localhost', 'list', true, false],
                      ['https://127.0.0.1', 'status', true, false],
                      ['https://localhost', 'list', true, false]
                     ]
      invalid_args.each do |args|
        expect { PerforceSwarm::GitFusion.extend_url(*args) }.to raise_error(RuntimeError)
      end
    end
  end
end
