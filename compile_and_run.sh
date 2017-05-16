#!/bin/sh
ERRCOUNT=0
echo "======================="
echo "==       ASURO       =="
echo "======================="
if [ "%1" == "-d"]
then
	./compile.sh -d
else
	./compile.sh
fi
./run.sh
