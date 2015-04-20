#!/bin/bash
#
# gitlab-shell-merge-master.sh
#
# Merges the 'P4GitLab/gitlab-shell' integration-prep-ce branch to prep
# Called as a result of a successful integration-prep-ce Jenkins test

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

# Logs
now=$(date "+%Y-%m-%d-%H%M")

echo "::: ${now} Merging integration-prep-ce into prep :::"
cd ../.. 
echo $(pwd)

# Update from origin
echo "::: Updating local branches :::"
git fetch --all

# Update master and integration-prep-ce
git checkout integration-prep-ce
git rebase origin/integration-prep-ce
git checkout prep 
git rebase origin/prep

# Merge from integration-prep-ce to prep
bomb_if_bad git merge integration-prep-ce -m "Merging integration-prep-ce into prep"

# Mail the log
cat $LOGFILE | mail -s "${REPO}-merge-prep.sh - ${now}" juytven@perforce.com
