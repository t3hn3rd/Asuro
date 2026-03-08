#!/usr/bin/env bash
echo > checksums.md5
for directory in $(find src/ -maxdepth 10 -type d); do
	for filename in $directory/*.pas; do
		if [[ $filename == *".svn"* ]]; then
			continue
		else
			if [[ $filename == *"*.pas"* ]]; then
				continue
			else
				if [[ $filename = *"include/asuro.pas"* ]]; then
					continue
				else
					md5sum $filename >> checksums.md5
				fi
			fi
		fi		
	done
done
