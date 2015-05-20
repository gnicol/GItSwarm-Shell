#!/bin/bash
#
# Gitlab-shell Integration Script
#
# Merges Community master into our integration-ce branch,
# and merges the community master tag on its master as the
# source for changes to merge prep with.
#
# If a branch merges cleanly, we sweep down right away to
# the master and prep branches, as we have no tests to
# run against them at the moment.

# Make sure we use the Ruby version in rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

function bomb_if_bad {
	echo "$@" 
	local status=$?
	if [ $status -ne 0 ]; then
		echo "::: CONFLICT!!! :::" 
		exit 1
	fi
	return $status
}

REPO="gitlab-shell"
REPODIR="${HOME}/integration-ce/${REPO}"

# Set by Jenkins, uncomment and set if you want to run standalone
# STABLE_TAG=

# Logs
now=$(date "+%Y-%m-%d-%H%M")
ruby_loc=`which ruby`                                         
ruby_ver=`ruby -v`                                            
bundle_loc=`which bundle`   
echo "::: ${now} Integrating Community master/stable into ${REPO} :::"
echo "::: Using ${ruby_ver} from ${ruby_loc} :::"
echo "::: Bundler is at: ${bundle_loc} :::"

# Update the master, prep, integration-ce and integration-prep-ce
# branches from origin
echo "::: Fetching from remotes :::"
git fetch --all 
echo "::: Merging origin changes, Should only be fast-forwards :::"
echo "::: Merging origin/master -> master :::"
git checkout master
git rebase origin/master 
echo "::: Merging origin/prep -> prep :::"
git checkout prep
git rebase origin/prep
echo "::: Merging origin/integration-ce -> integration-ce :::"
git checkout integration-ce
git rebase origin/integration-ce
echo "::: Merging origin/integration-prep-ce -> integration-prep-ce :::"
git checkout integration-prep-ce
git rebase origin/integration-prep-ce

# Update integration-ce with changes from master
# If this results in a conflict we make a note and exit.
echo "::: Copy-up master -> integration-ce :::"
git checkout integration-ce
bomb_if_bad git merge --strategy-option theirs master -m "Copy-up master into integration-ce"

# Update integration-prep-ce with changes from prep
# If this results in a conflict we make a note and exit.
echo "::: Copy-up prep -> integration-prep-ce :::"
git checkout integration-prep-ce
bomb_if_bad git merge --strategy-option theirs prep -m "Copy-up prep into integration-prep-ce"

# Now merge the Community master into integration-ce
echo "::: Merging gitlab-shell/master -> integration-ce :::"
git checkout integration-ce
bomb_if_bad git merge origin/community-master -m "Merging community into master"

# Push integration-ce to origin and push
git push origin integration-ce

# Update integration-prep-ce with changes from stable tag.  This should
# always be a clean, nothing-added merge
echo "::: Merging in community ${STABLE_TAG} tag -> integration-prep-ce :::"
git checkout integration-prep-ce
bomb_if_bad git merge ${STABLE_TAG} -m "Merging ${STABLE_TAG}"

# Push integration-prep-ce to origin and push
git push origin integration-prep-ce

# Reset to master branch
git checkout master
echo $now
