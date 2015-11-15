#!/bin/sh
###############################################################################
# PURPOSE:	Set the git timestamps to the original file timestamp
#		of various files when adding them to a new git repository 
#
# AUTHOR:	D. Deatrich
# DATE:		Oct 2015
#
# RETURNS:	0  - OK
#		1  - something bad happened .. see the script output
#
# USAGE:	(you can set GIT_MSG env var when using this script)
#  $ GIT_MSG="some info msg" git-add-commit-ts.sh -y some-file1 some-file2 ...
#
###############################################################################
#set -v		# debugging tools
#set -x

unalias -a
PATH="/bin:/usr/bin"

cmd=`basename $0`
dbg=""
usagestr="\n
USAGE:\t$cmd COMMIT_TARGET [ -y ]\n
WHERE:\tCOMMIT_TARGET\t specifies one or more files to add/commit to git\n
\t-y\t means really do it"

## exit in error with an informative message
function err_exit() {
  echo -e $1
  exit 1
}

## function that prints out a usage string and exits abnormally
usage() {
  err_exit "$usagestr"
}

if [ $# -lt 1 ] ; then
  usage
fi

doit="no"
args=""
while [ $1 ] ; do
  case $1 in
    -h)  usage ;; 
    -y)  doit="yes" ;; 
     *)  args=$args" "$1 ;;
  esac
  shift
done
if [ "$args" = "" ] ; then
  usage
fi

if [ "$doit" != "yes" ] ; then
  dbg="echo"
fi

for F in $args ; do
  if [ ! -f $F ] ; then
    echo "$F is not a file"
  else
    export GIT_COMMITTER_DATE=$(date -r $F)
    export GIT_AUTHOR_DATE=$(date -r $F)
    $dbg git add $F
    if [  "$GIT_MSG" != "" ] ; then
      $dbg git commit -m "$GIT_MSG" $F
    else
      $dbg git commit $F
    fi
    unset GIT_COMMITTER_DATE
    unset GIT_AUTHOR_DATE
  fi
done

