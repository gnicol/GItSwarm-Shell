#!/bin/bash
#
# Merge one branch into another, and push back to repo.
# relies on SRC_BRANCH and DST_BRANCH be set in the
# environment.  For use by Jenkins.

function bomb_if_bad {
	"$@" 2>&1 
	local status=$?
	if [ $status -ne 0 ]; then
		echo "::: CONFLICT!!! :::"
		exit 1
	fi
	return $status
}

REPO="gitlab-shell"

# Jenkins specifies these two.  Set manually if not using Jenkins
# SRC_BRANCH=
# DST_BRANCH=


# Logs
now=$(date "+%Y-%m-%d-%H%M")

echo "::: ${now} Merging ${SRC_BRANCH} into ${DST_BRANCH} :::"

# Update from origin
echo "::: Fetching changes from origin :::"
git fetch --all

# Update the branches
echo "::: Updating ${SRC_BRANCH} :::" 
git checkout $SRC_BRANCH 
git merge origin/$SRC_BRANCH
echo "::: Updating ${DST_BRANCH} :::"
git checkout $DST_BRANCH
git merge origin/$DST_BRANCH

# Merge from src to dst
echo "::: Merging ${SRC_BRANCH} into ${DST_BRANCH} :::"
git checkout $DST_BRANCH
bomb_if_bad git merge $SRC_BRANCH -m "Merging ${SRC_BRANCH} into ${DST_BRANCH}"

# Push back to origin
echo "::: Pushing ${DST_BRANCH} to origin :::"
git push origin $DST_BRANCH
