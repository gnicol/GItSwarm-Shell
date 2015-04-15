#!/bin/bash
#
# gitlab-shell-merge-master.sh
#
# Merges the 'P4GitLab/gitlab-shell' integration-ce branch to master
# Called as a result of a successful integration-ce Jenkins test

function bomb_if_bad {
	"$@" 2>&1 
	local status=$?
	if [ $status -ne 0 ]; then
		echo "::: CONFLICT!!! :::" 2>&1 
		exit 1
	fi
	return $status
}

REPO="gitlab-shell"
REPODIR="${HOME}/integration-ce/${REPO}"

# Logs
now=$(date "+%Y-%m-%d-%H%M")

echo "::: ${now} Merging integration-ce into master :::"
cd ../.. 
echo $(pwd)

# Update from origin
echo "::: Updating local branches :::"
git fetch --all

# Update master and integration-ce
git checkout integration-ce
git rebase origin/integration-ce
git checkout master
git rebase origin/master

# Merge from integration-ce to master
bomb_if_bad git merge integration-ce -m "Merging integration-ce into master"

# Mail the log
cat $LOGFILE | mail -s "${REPO}-merge-master.sh - ${now}" juytven@perforce.com
