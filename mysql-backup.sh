#!/bin/bash
###############################################################################
#
# PURPOSE:	This is an example script for mysql/mariadb backups with
#		lots of error checking.
#		
# AUTHOR:	D. Deatrich
#
# RETURNS:	0  - OK
#		1  - an error occured .. see the script output
#
# USAGE:	See usage string in the script
# NOTES:	The system 'root' user must be allowed to log into mysql without
#		a password in this script.  Otherwise you will need to modify
#		this script to use a password, or get one from ~/.my.cnf
#
# LOGIC:	Local backups:
#		  All system and user databases are dumped and compressed into 
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
###############################################################################
#set -v		# debugging tools
#set -x

unalias -a
PATH="/bin:/usr/bin"

g_cmd=$(basename $0)

g_debug="no"

## this function allows us to debug and echo verbose info in testing mode
function f_dbg() {
  if [ "$g_debug" = "no" ] ; then
    return 1
  else
    return 0
  fi
}

## The configuration file sets '$logdir' and '$localtarget' used by this script
conf="/etc/mysql-backup.conf"
if [ ! -f $conf ] ; then
  echo "Missing configuration file '$conf'"
  exit 1
fi
. $conf

if [ ! -d "$logdir" ] ; then
  echo "Missing logging directory '$logdir'"
  exit 1
fi
permlogfile=$logdir"/mysql-backups.log"

usagestr="\
USAGE:\t$g_cmd [--test] 
WHERE:\t--test\t\t-- output debug messages about what you would do"

function f_usage() {
  echo -e "$usagestr"
  exit 1
}

## parse cmd-line args (in case we add more options later)
while [ $1 ] ; do
  case $1 in
      --test) g_debug="yes";;
  esac
  shift
done

function f_datestring() {
  s="$1"
  date=$(date +"%b %d %H:%M:%S")
  echo "$date $s"
}

function f_errexit() {
  msg=$(f_datestring "$1")
  f_dbg && echo "$g_cmd: $msg"
  f_dbg || echo "$msg" >> $permlogfile
  exit 1
}

id=$(id -u)
if [ $id -ne 0 ] ; then
  echo "You are not root"
  exit 1
fi

dir="/var/lib/mysql"
if [ ! -d $dir ] ; then
  echo "MySQL directory '$dir' does not exist"
  exit 1
fi

## if testing is false then from here we log messages in the log '$permlogfile'
if [ ! -d "$localtarget" ] ; then
  f_errexit "Missing backups directory '$localtarget'"
else
  cd $localtarget
  if [ $? -ne 0 ] ; then
    f_errexit "Cannot change directories to '$localtarget'"
  fi
fi

## Let's check available disk space before doing backups
typeset -i destsize
destsize=`df -k $localtarget|awk '{print $2}'|grep -v blocks`

typeset -i sum
sum=0
f_dbg && echo "Check available disk space:"
dir="/var/lib/mysql"
sum=`du -sk $dir|awk '{print $1}'`
f_dbg && echo -n " In '$dir' the space used is: $sum; "

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
 
opts="--opt --add-locks --single-transaction"
databases=$(mysql -u root -Bse "show databases;")
errmsg=""
if [ "$databases" != "" ] ; then
  f_dbg && echo mkdir mysql
  f_dbg || errmsg=$(mkdir mysql 2>&1) 
  if [ $? -ne 0 ] ; then
    f_errexit "$errmsg"
  fi
  for db in $databases ; do
    dest="mysql/$db.dump"
    f_dbg && echo mysqldump -u root $opts --databases $db \> $dest
    f_dbg || errmsg=$(mysqldump -u root $opts --databases $db > $dest 2>&1)
    if [ $? -ne 0 ] ; then
      f_errexit "$errmsg"
    fi
  done
fi
f_dbg && echo tar zcf mysql.tar.gz mysql
f_dbg || errmsg=$(tar zcf mysql.tar.gz mysql 2>&1)
if [ $? -ne 0 ] ; then
  f_errexit "$errmsg"
fi
f_dbg && echo /bin/rm -rf ./mysql/
f_dbg || /bin/rm -rf ./mysql/

if [ $? -eq 0 ] ; then
  msg=$(f_datestring "MySQL database backup finished.")
  f_dbg && echo "$msg"
  f_dbg || echo "$msg" >> $permlogfile
fi

exit 0

