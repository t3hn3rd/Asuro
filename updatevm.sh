#!/bin/sh
DIRECTORY="src/vm"
if [ -d "$DIRECTORY" ]; then
	cd "src/vm"
	svn update
	cd ".."
	cd ".."
else
	cd src
	svn checkout https://spexeah.com:8443/svn/MINJ/src/vm
fi
