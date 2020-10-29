#!/bin/sh
DIRECTORY="src/vm"
rm -rf /tmp/MINJ
git clone https://gitlab.spexeah.com/spexeah/MINJ.git /tmp/MINJ
rm -rf $DIRECTORY
cp -rf /tmp/MINJ/src/vm $DIRECTORY