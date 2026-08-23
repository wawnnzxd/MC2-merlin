#!/bin/sh

logpath=/tmp/upload
logmc=$logpath/merlinclash_log.txt

maxline=500

linecountmc=$(/usr/bin/wc -l $logmc | awk '{print $1}')

if [ "$linecountmc" -gt "$maxline" ]; then
    echo "" > $logmc
fi