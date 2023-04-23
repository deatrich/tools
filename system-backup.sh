#!/bin/bash
###############################################################################
#
# PURPOSE:	This is an example script for Linux system backups with
#		lots of error checking.
#		Note that we are backing-up files locally.  The best solution
#		is to then copy backed-up files to removable media, or
#		securely copy them to another device.
#
# AUTHOR:	D. Deatrich
#
# RETURNS:	0  - OK
#		1  - an error occured .. see the script output
#
# USAGE:	/path/to/system-backup.sh [ -y ]
# LOGIC:	Cycle through the days of the week, overwriting older backups
#		in what is known as a circular buffer.
#		As well, if you want to keep a year's worth of backups, but
#		effectively keep the last week of each month, then the buffer
#		is larger, but not overly expensive.
#		The final directory structure looks like this:
#		$ ls
#		01/  02/  03/  04/  05/  06/  07/  08/  09/  10/  11/  12/
#		$ ls 01  ## and all monthly directories look like this:
#		Fri/  Mon/  Sat/  Sun/  Thu/  Tue/  Wed/
#		
###############################################################################
#set -v		# debugging tools
#set -x

unalias -a
PATH="/usr/bin"

cmd=$(basename $0)


function errexit() {
  echo "$cmd: $1"
  exit 1
}

debug="true"
function dbg() {
  if [ "$debug" = "false" ] ; then
    return 1
  else
    return 0
  fi
}

function usage() {
  msg="means really do it.. else echo what it would do"
  usagestr="USAGE:\t$cmd [ -y ]\nWHERE:\t-y\t\t-- $msg"
  echo -e $usagestr
  exit 1
}

## parse cmd-line args
doit="no"
while [ $1 ] ; do
  case $1 in
    '-y') doit="yes"; debug="false";;
       *) usage;;
  esac
  shift
done

id=$(id -u)
if [ $id -ne 0 ] ; then
  errexit "You are not root"
fi

target="/var/local-backups"
if [ ! -d "$target" ] ; then
  errexit "Missing backups directory '$target'"
else
  cd $target
  if [ $? -ne 0 ] ; then
    errexit "Cannot change directories to '$target'"
  fi
fi

## list of directories to backup up:
sysdirs="/etc /home /var/log /var/www /root"

## Let's check available disk space before doing backups
typeset -i destsize
destsize=`df -k $target | awk '{print $2}'|grep -v blocks`

typeset -i tmpsum
typeset -i sum
sum=0
for dir in $sysdirs ; do
  if [ -d $dir ] ; then
    tmpsum=`du -sk $dir|awk '{print $1}'`
    sum=$sum+$tmpsum
    dbg && echo -n " In $dir space used is: $tmpsum; "
    dbg && echo " Total space required is now: $sum"
  fi
done

## Note that we will compress the backed-up files, so we will need
## less space then is assumed here; that is okay - don't pinch the filesystem
dbg && echo " Kbytes of space available: $destsize and space needed: $sum"
sum=$sum+500000		## add a buffer of half a megabyte
dbg && echo " Required space with half a megabyte buffer is: $sum"
if [ $destsize -lt $sum ] ; then
  errexit "There is not enough space to backup files in $target"
else
  dbg && echo " We are okay for space to backup files in $target"
fi

today=$(date +%a)	## short form of the day of the week in your language
month=$(date +%m)	## numeric value for current month
folder=$month"/"$today
if [ ! -d "$folder" ] ; then
  mkdir -p $folder
  if [ $? -ne 0 ] ; then
    errexit "Could not make directory to '$target/$folder'"
  fi
fi
cd $target/$folder
if [ $? -ne 0 ] ; then
  errexit "Cannot change directories to '$target/$folder'"
fi
 
for dir in $sysdirs ; do
  if [ -d $dir ] ; then
    ## remove the leading slash, and replace subsequent ones with '_'
    name=$(echo $dir | sed 's%/%%' | sed 's%/%_%g')
    dbg && echo tar --ignore-failed-read -zcf $name".tgz" $dir
    if [ "$doit" = "yes" ] ; then
      tar --ignore-failed-read -zcf $name".tgz" $dir
    fi
  fi
done

exit 0
### To Do: provide data backup example to a usb device

### you need to prepare the usb device - identify it, make file system
### on it if necessary, and create the backup directory on it
### Then for backups mount it, copy the local data backups to it and unmount it.
usbdev="/dev/sda"
usbpartition="/dev/sda1"
mntpoint="/mnt/backups"

exit 0

