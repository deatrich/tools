#!/bin/bash
###############################################################################
#
# PURPOSE:	This is an example script for Linux system backups with
#		lots of error checking.
#		
# AUTHOR:	D. Deatrich
#
# RETURNS:	0  - OK
#		1  - an error occured .. see the script output
#
# USAGE:	see usage string in the script
# LOGIC:	Local backups:
#		  A specified list of directories is each compressed into 
#		  a 'tar' archive and stored on the local disk.  The script
#		  cycles through the days of the week, overwriting older backups
#		  in what is known as a circular buffer.
#		  The script also starts a new top directory for a new month,
#		  using the month number.  This effectively keeps the last
#		  week of each month only. The buffer is larger, but not
#		  overly big.
#		  The final directory structure looks like this:
#		  $ ls      ## (the months of a year by number)
#		  01/  02/  03/  04/  05/  06/  07/  08/  09/  10/  11/  12/
#
#		  All monthly directories look like this:
#		  $ ls 01
#		  Fri/  Mon/  Sat/  Sun/  Thu/  Tue/  Wed/
#
#		External backups (to a removable device):
#		  This is a simple local rsync of the contents of the 
#		  local backups to the removable device
#
#		Large directory backups (to a removable device):
#		  This is a simple local rsync of the specified large 
#		  directories to a removable device.  The schedule of
#		  the backups is determined by your configuration value
#		  for 'rsync_days', as well as your cron job frequency.
#
#		Large directory synchronization (to a removable device):
#		  This is an option that would typically be done from time
#		  to time (to maintain a true extra copy of large directories).
###############################################################################
#set -v		# debugging tools
#set -x

unalias -a
PATH="/bin:/usr/bin"

cmd=$(basename $0)

debug="no"
function f_dbg() {
  if [ "$debug" = "no" ] ; then
    return 1
  else
    return 0
  fi
}

conf="/etc/system-backup.conf"
if [ ! -f $conf ] ; then
  echo "Missing configuration file '$conf'"
  exit 1
fi
. $conf

if [ ! -d "$logdir" ] ; then
  echo "Missing logging directory '$logdir'"
  exit 1
fi
permlogfile=$logdir"/backups.log"

function f_errexit() {
  date=$(date +"%b %d %H:%M:%S")
  f_dbg && echo "$cmd: $1"
  f_dbg || echo "$date $1" >> $permlogfile
  exit 1
}

usagestr="\
USAGE:\t$cmd [--test] [--local] [ ---external ] [ --rsync-large ]
WHERE:\t--test\t\t-- output debug messages about what you would do
\t--local\t\t-- do local backups
\t--external\t-- write today's backed up data to the external device
\t--rsync-large\t-- rsync large files to the external device
\t--rsync-copy\t-- on-demand update of latest rsync backup on external device"

function f_usage() {
  echo -e "$usagestr"
  exit 1
}

local="no"
extern="no"
rsync="no"
rcopy=""
function f_getargs() {
  ## parse cmd-line args
  if [ $# -lt 1 ] ; then
    f_usage
  fi
  while [ $1 ] ; do
    case $1 in
                --test) debug="yes";;
               --local) local="yes";;
            --external) extern="yes";;
         --rsync-large) rsync="yes";;
          --rsync-copy) shift
                        if [ $1 ] ; then
                          re='^[0-6]$'
                          if [[ $1 =~ $re ]] ; then
                            rcopy="$1"
                          else
                            f_errexit "'$1' must be a number from 0 through 6"
                          fi
                        else
                          f_usage
                        fi ;;
                     *) f_usage;;
    esac
    shift
  done
}

mounted="no"
function f_prep_external() {
  if [ "$mounted" = "yes" ] ; then
    return;
  fi
  lsblk | grep -q "$usbpartition"
  if [ $? -ne 0 ] ; then
    f_errexit "Partition '/dev/$usbpartition' for external backups not seen"
  else
    grep -q "$mntpoint" /etc/mtab
    if [ $? -eq 0 ] ; then
      f_errexit "'$mntpoint' is already mounted - please check"
    fi
  fi
  f_dbg && echo mount /dev/$usbpartition $mntpoint
  mount /dev/$usbpartition $mntpoint
  if [ $? -ne 0 ] ; then
    f_errexit "Could not mount partition '/dev/$usbpartition'"
  else
    mounted="yes"
  fi
}

f_getargs "$@"

id=$(id -u)
if [ $id -ne 0 ] ; then
  f_errexit "You are not root"
fi

if [ ! -d "$localtarget" ] ; then
  f_errexit "Missing backups directory '$localtarget'"
else
  cd $localtarget
  if [ $? -ne 0 ] ; then
    f_errexit "Cannot change directories to '$localtarget'"
  fi
fi

tmplogfile="/tmp/local-backup_"$$
if [ "$local" = "yes" ] ; then
  ## Let's check available disk space before doing backups
  typeset -i destsize
  destsize=`df -k $localtarget|awk '{print $2}'|grep -v blocks`

  typeset -i tmpsum
  typeset -i sum
  sum=0
  for dir in $sysdirs ; do
    if [ -d $dir ] ; then
      tmpsum=`du -sk $dir|awk '{print $1}'`
      sum=$sum+$tmpsum
      f_dbg && echo -n " In $dir space used is: $tmpsum; "
      f_dbg && echo " Total space required is now: $sum"
    fi
  done

  ## Note that we will compress the backed-up files, so we will need
  ## less space then is assumed here; that is okay - don't pinch the filesystem
  f_dbg && echo " Kbytes of space available: $destsize and space needed: $sum"
  sum=$sum+500000		## add a buffer of half a megabyte
  f_dbg && echo " Required space with half a megabyte buffer is: $sum"
  if [ $destsize -lt $sum ] ; then
    f_errexit "There is not enough space to backup files in $localtarget"
  else
    f_dbg && echo " We are okay for space to backup files in $localtarget"
  fi

  today=$(date +%a)	## short form of the day of the week in your language
  month=$(date +%m)	## numeric value for current month
  folder=$month"/"$today
  if [ ! -d "$folder" ] ; then
    mkdir -p $folder
    if [ $? -ne 0 ] ; then
      f_errexit "Could not make directory '$localtarget/$folder'"
    fi
  fi
  cd $localtarget/$folder
  if [ $? -ne 0 ] ; then
    f_errexit "Cannot change directories to '$localtarget/$folder'"
  fi
 
  for dir in $sysdirs ; do
    if [ -d $dir ] ; then
      ## remove the leading slash, and replace subsequent ones with '_'
      name=$(echo $dir | sed 's%/%%' | sed 's%/%_%g')
      f_dbg && echo tar --ignore-failed-read -zcf $name".tgz" $dir

      f_dbg || tar --ignore-failed-read -zcf $name".tgz" $dir >>$tmplogfile 2>&1
    fi
  done
  if [ -e "$tmplogfile" ] ; then  ## else we are in debug mode
    output=$(grep -c -v "tar: Removing leading \`/' from member names" $tmplogfile)
    if [ "$output" != "0" ] ; then
      cat  "$output" >> $permlogfile
      echo "$output"
    fi
    rm -f $tmplogfile 2>/dev/null
  fi
fi

if [ "$extern" = "yes" ] ; then
  f_prep_external
  if [ ! -d "$usb_local_dirs" ] ; then
    umount $mntpoint
    f_errexit "Missing directory '$usb_local_dirs'"
  else
    f_dbg && echo rsync -aux $localtarget/ $usb_local_dirs/
    f_dbg || rsync -aux $localtarget/ $usb_local_dirs/ >>$tmplogfile 2>&1
    res=$?
    if [ -f "$tmplogfile" ] ; then
      cat  "$tmplogfile" >> $permlogfile
      rm -f $tmplogfile 2>/dev/null
    fi
    if [ $res -ne 0 ] ; then
      umount $mntpoint
      f_errexit "rsync from '$localtarget' to '$usb_local_dirs' had a problem"
    fi
    f_dbg && echo umount $mntpoint
    umount $mntpoint
    mounted="no"
  fi
fi
if [ "$rsync" = "yes" ] ; then
  if [ "$rsync_days" = "" ] ; then
    f_errexit "Missing value for 'rsync_days' - the days of the week for rsyncs"
  fi
  dayofweek=$(date +%w)
  do_rsync="no"
  for i in $rsync_days ; do
    if [ "$i" = "$dayofweek" ] ; then
      do_rsync="yes"
      continue
    fi
  done
  if [ "$do_rsync" = "no" ] ; then
    f_dbg && echo We do not do rsync backups for large directories today
    exit 0
  fi
  f_prep_external
  if [ ! -d "$usb_large_dirs" ] ; then
    umount $mntpoint
    f_errexit "Missing directory '$usb_large_dirs'"
  else
    folder=$usb_large_dirs"/"$dayofweek
    if [ ! -d "$folder" ] ; then
      mkdir -p $folder
      if [ $? -ne 0 ] ; then
        f_errexit "Could not make directory '$folder'"
      fi
    fi
    for dir in $largedirs ; do
      if [ -d $dir ] ; then
        ## remove the leading slash, and replace subsequent ones with '_'
        name=$(echo $dir | sed 's%/%%' | sed 's%/%_%g')
        f_dbg && echo nice -n 19 rsync -aux $dir/ $usb_large_dirs/$dayofweek/$name
        f_dbg || nice -n 19 rsync -aux $dir/ $usb_large_dirs/$dayofweek/$name >>$tmplogfile 2>&1
        res=$?
        if [ -f "$tmplogfile" ] ; then
          cat  "$tmplogfile" >> $permlogfile
          rm -f $tmplogfile 2>/dev/null
        fi
        if [ $res -ne 0 ] ; then
          umount $mntpoint
          f_errexit "rsync from '$localtarget' to '$usb_large_dirs' had a problem"
        fi
      fi
    done
  fi
  f_dbg && echo umount $mntpoint
  umount $mntpoint
  mounted="no"
fi
if [ "$rcopy" != "" ] ; then
  f_prep_external
  if [ ! -d "$usb_large_copy" ] ; then
    umount $mntpoint
    f_errexit "Missing directory '$usb_large_copy'"
  fi
  if [ ! -d "$usb_large_dirs/$rcopy" ] ; then
    umount $mntpoint
    f_errexit "Missing directory '$usb_large_dirs/$rcopy'"
  else
    f_dbg && echo nice -n 19 rsync -aux --delete \
      $usb_large_dirs/$rcopy/ $usb_large_copy/
    f_dbg || nice -n 19 rsync -aux --delete \
      $usb_large_dirs/$rcopy/ $usb_large_copy/ >>$tmplogfile 2>&1
    res=$?
    if [ -f "$tmplogfile" ] ; then
      cat  "$tmplogfile" >> $permlogfile
      rm -f $tmplogfile 2>/dev/null
    fi
    if [ $res -ne 0 ] ; then
      umount $mntpoint
      f_errexit "rsync from" "\
       '$usb_large_dirs/$rcopy/' to '$usb_large_copy/' had a problem"
    fi
  fi
  f_dbg && echo umount $mntpoint
  umount $mntpoint
  mounted="no"
fi

exit 0

