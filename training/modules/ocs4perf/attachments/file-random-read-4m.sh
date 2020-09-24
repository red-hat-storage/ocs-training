#!/bin/bash
echo "Currently mounted filesystems for Random READ test"
df | grep 'data'
echo "Changing working directory to /tmp/data"
cd /tmp/data
echo "Current working directory for control before execution"
pwd
set -x
sysbench --threads=16 --test=fileio --file-total-size=512m --file-test-mode=rndrd --file-block-size=4m  --file-io-mode=async --file-fsync-freq=0 prepare
set +x
pwd >/tmp/trace.txt;ls >>/tmp/trace.txt
set -x
sysbench --threads=16 --test=fileio --file-total-size=512m --file-test-mode=rndrd --file-block-size=4m --file-extra-flags=dsync run
sysbench --threads=16 --test=fileio --file-total-size=512m --file-test-mode=rndrd --file-block-size=4m --file-io-mode=async --file-fsync-freq=0 cleanup
set +x
echo "Changing working directory to $HOME"
cd ~
