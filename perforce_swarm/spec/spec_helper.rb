require File.expand_path('../../../spec/spec_helper', __FILE__)

def add_mirror(repo_path, mirror_url)
  cmd = %W(git --git-dir=#{repo_path} remote add mirror #{mirror_url})
  system(*cmd)
end

def build_gitlab_projects(*args)
  argv(*args)
  gl_projects = GitlabProjects.new
  gl_projects.stub(repos_path: tmp_repos_path)
  gl_projects.stub(full_path: File.join(tmp_repos_path, gl_projects.project_name))
  gl_projects
end

def argv(*args)
  args.each_with_index do |arg, i|
    ARGV[i] = arg
  end
end
