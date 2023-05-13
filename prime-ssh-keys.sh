#!/bin/bash
###############################################################################
# PURPOSE:	This script creates an ssh-agent, and it writes ssh agent info
#		to the file '~/.ssh-agent-info-`hostname`'. It then prompts
#		the user for key passphrase(s).  Then any shell can use the 
#		agent by sourcing the contents of the generated agent file; eg:
#		     . ~/ssh-agent-info-`hostname`   
#		or
#		     source ~/ssh-agent-info-`hostname`   
#
# AUTHOR:	D. Deatrich
#
# RETURNS:	The return code will be the result of 'ssh-add'.  In case of 
#		failure (you forgot your ssh passphrase maybe and aborted?)
#		then there will be a useless ssh-agent process running ...
#
# USAGE:	~/bin/prime-ssh-keys.sh
#
###############################################################################

## safely limit the PATH var when back-quoting command output; i.e. hostname
PATH=/usr/bin
unalias -a

ssh_info_file=$HOME/.ssh-agent-info-`hostname`
export ssh_info_file
ssh-agent | grep -v '^echo ' > $ssh_info_file
chmod 600 $ssh_info_file
source $ssh_info_file

## If you have non-standard private key names then pass them as args instead:
#ssh-add ~/.ssh/id_rsa ~/.ssh/id_rsa_github
## otherwise let ssh-add find your standard private key names:
ssh-add

