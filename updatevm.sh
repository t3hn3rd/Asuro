#!/bin/sh
DIRECTORY="src/vm"
if [ -d "$DIRECTORY" ]; then
	cd "src/vm"
	svn update
	cd ".."
	cd ".."
else
	cd src
	svn checkout http://ovh.spexeah.com:81/svn/MINJ/src/vm
fi
