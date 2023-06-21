#!/bin/bash
## Generate an OpenSSL server private key, a signing request, and a self-signed
## certificate.  Edit the configuration file 'addcert.cnf' and set values
## that correspond to your server data.
## We generate a certificate that is valid for 10 years ...

unalias -a
PATH=/usr/bin
export PATH

cmd=$(basename $0)

function errexit() {
  echo "$cmd: $1"
  exit 1
}

## Configuration file in the same directory where you generate your files.
conf="./addcert.cnf"
if [ ! -f $conf ] ; then
  errexit "Missing configuration file '$conf'"
fi

## Private server key
keyfile="server.key"
if [ -f "$keyfile" ] ; then
  errexit "Key file '$keyfile' exists in this directory"
fi

## certificate signing request
csrfile="server.csr"
if [ -f "$csrfile" ] ; then
  errexit "Certificate signing request file '$csrfile' exists in this directory"
fi

## Self-signed certificate
crtfile="server.crt"
if [ -f "$crtfile" ] ; then
  errexit "Certificate file '$crtfile' exists in this directory"
fi

## generate private key
/usr/bin/openssl genrsa -rand /proc/cpuinfo:/proc/filesystems:/proc/interrupts:/proc/ioports:/proc/uptime 4096 > $keyfile 2>/dev/null

res=$?
if [ $res != 0 ] ; then
  errexit "openssl failed to generate '$keyfile'"
fi

## generate certificate signing request
echo openssl req -new -key server.key -config addcert.cnf -out $csrfile
openssl req -new -key server.key -config addcert.cnf -out $csrfile 2>/dev/null

res=$?
if [ $res != 0 ] ; then
  errexit "openssl failed to generate '$csrfile'"
fi

## generate certificate good for 10 years :-O
openssl x509 -req -days 3650 -in server.csr -signkey server.key -out server.crt

res=$?
if [ $res != 0 ] ; then
  errexit "openssl failed to generate '$csrfile'"
fi

## Correct Permissions:
chmod 400 server.key
chmod 444 server.csr
chmod 444 server.crt

ls -l server.*
sleep 1 

echo "$cmd:  SVP copy server files into place and change ownership to root"

