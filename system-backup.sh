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
PATH="/bin:/usr/bin"

cmd=$(basename $0)

function errexit() {
  echo "$cmd: $1"
  exit 1
}

conf="/etc/system-backup.conf"
if [ ! -f $conf ] ; then
  errexit "Missing configuration file '$conf'"
fi

. $conf

debug="no"
function dbg() {
  if [ "$debug" = "no" ] ; then
    return 1
  else
    return 0
  fi
}

function usage() {
  D="output debug messages about what you would do"
  Y="means really do local backups"
  X="means write the backed up data to the external device"
  usagestr="USAGE:\t$cmd [ -D ] [-Y] [ -X ]\nWHERE:\t-D\t-- $D\n\t-Y\t-- $Y\n\t-X\t-- $X"
  echo -e $usagestr
  exit 1
}

## parse cmd-line args
if [ $# -lt 1 ] ; then
  usage
fi

doit="no"
external="no"
while [ $1 ] ; do
  case $1 in
    '-D') debug="yes";;
    '-Y') doit="yes";;
    '-X') external="yes";;
       *) usage;;
  esac
  shift
done

dbg && echo "debug is $debug, backup is $doit, external copy is $external"

id=$(id -u)
if [ $id -ne 0 ] ; then
  errexit "You are not root"
fi

if [ ! -d "$localtarget" ] ; then
  errexit "Missing backups directory '$localtarget'"
else
  cd $localtarget
  if [ $? -ne 0 ] ; then
    errexit "Cannot change directories to '$localtarget'"
  fi
fi

if [ "$doit" = "yes" ] ; then
  ## Let's check available disk space before doing backups
  typeset -i destsize
  destsize=`df -k $localtarget | awk '{print $2}'|grep -v blocks`

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
    errexit "There is not enough space to backup files in $localtarget"
  else
    dbg && echo " We are okay for space to backup files in $localtarget"
  fi

  today=$(date +%a)	## short form of the day of the week in your language
  month=$(date +%m)	## numeric value for current month
  folder=$month"/"$today
  if [ ! -d "$folder" ] ; then
    mkdir -p $folder
    if [ $? -ne 0 ] ; then
      errexit "Could not make directory to '$localtarget/$folder'"
    fi
  fi
  cd $localtarget/$folder
  if [ $? -ne 0 ] ; then
    errexit "Cannot change directories to '$localtarget/$folder'"
  fi
 
  for dir in $sysdirs ; do
    logfile="/tmp/local-backup_"$$
    if [ -d $dir ] ; then
      ## remove the leading slash, and replace subsequent ones with '_'
      name=$(echo $dir | sed 's%/%%' | sed 's%/%_%g')
      if [ "$doit" = "yes" ] ; then
        if [ "$debug" = "yes" ] ; then
          echo tar --ignore-failed-read -zcf $name".tgz" $dir
        else
          tar --ignore-failed-read -zcf $name".tgz" $dir >>$logfile 2>&1
        fi
      fi
    fi
  done
  if [ -e "$logfile" ] ; then  ## else we are in debug mode
    output=$(grep -c -v "tar: Removing leading \`/' from member names" $logfile)
    if [ "$output" != "0" ] ; then
      echo "$output"
    fi
    rm -f $logfile 2>/dev/null
  fi
fi

if [ "$external" = "yes" ] ; then
  lsblk | grep -q "$usbpartition"
  if [ $? -ne 0 ] ; then
    errexit "Partition '/dev/$usbpartition' for external backups not seen"
  else
    grep -q "$mntpoint" /etc/mtab
    if [ $? -eq 0 ] ; then
      errexit "'$mntpoint' is already mounted - please check"
    fi
  fi
  dbg && echo mount /dev/$usbpartition $mntpoint
  mount /dev/$usbpartition $mntpoint
  if [ $? -ne 0 ] ; then
    errexit "Could not mount partition '/dev/$usbpartition'"
  else
    if [ ! -d "$usbtarget" ] ; then
      umount $mntpoint
      errexit "Missing directory '$usbtarget'"
    else
      dbg && echo rsync -aux $target $usbtarget
      if [ "$external" = "yes" ] ; then
        if [ "$debug" = "yes" ] ; then
          echo rsync -aux $target $usbtarget
        else
          rsync -aux $target $usbtarget
        fi
        if [ $? -ne 0 ] ; then
          umount $mntpoint
          errexit "Note - rsync from '$target' to '$usbtarget' had a problem"
        fi
      fi
      dbg && echo umount $mntpoint
      umount $mntpoint
    fi
  fi
fi

exit 0

