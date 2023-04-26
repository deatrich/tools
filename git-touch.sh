#!/bin/bash -e
###############################################################################
# PURPOSE:	Update all file timestamps to the original timestamp on
#		pulled target git repository
#
# RETURNS:	0    - OK
#		1    - error
#
# USAGE:	
# WHERE:	
#
# BORROWED/ADAPTED FROM:
# http://stackoverflow.com/questions/1964470/whats-the-equivalent-of-use-commit-times-for-git
# https://copyprogramming.com/howto/git-commit-only-timestamp-modification-of-a-file
#
# CHANGES:	DCD at TRIUMF:
#		- modified to test for file existance before updating timestamp
#		- removed get_file_rev fnc, and use git-log instead of git-show
###############################################################################

unalias -a
PATH=/usr/bin:/bin

update_file_timestamp() {
  file_time=$(git log -1 --pretty=format:%ai "$1")
  touch -d "$file_time" "$1"
}

OLD_IFS=$IFS
IFS=$'\n'

for file in `git ls-files`
do
  if [ -f "$file" ] ; then
    update_file_timestamp "$file"
  fi
done

IFS=$OLD_IFS

git update-index --refresh

