#!/bin/bash
echo " "
echo "======================="
echo " "
echo "Generating Documentation..."
echo " "
echo "Dowloading Pasdoc..."
wget https://github.com/pasdoc/pasdoc/releases/download/v0.16.0/pasdoc-0.16.0-linux-x86_64.tar.gz -O pasdoc.tar.gz
echo "Extracting Pasdoc..."
tar -xf pasdoc.tar.gz
echo "Creating doc output directory..."
mkdir ./doc
echo "Removing old docs"
rm -rf ./doc/*
echo "Generating Docs..."
./pasdoc/bin/pasdoc -N "Asuro" -T "Asuro OS Documentation" -O "html" -E ./doc/ -S sources.list --use-tipue-search
echo "Docgen finished."
exit 0