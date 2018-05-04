#!/bin/bash
outfile="src/include/asuro.pas"
file="version"
while IFS=: read -r line;do
	major=$(echo $line | awk '{print $1}')
	minor=$(echo $line | awk '{print $2}')
	sub=$(echo $line | awk '{print $3}')
	release=$(echo $line | awk '{print $4}')
	linecount=$(./loc.sh | awk '{print $1}')
done <"$file"
revision=$(svn info | grep Revision | awk '{print $2}')
echo $major"."$minor"."$sub"-r"$revision$release
echo "unit asuro;" > $outfile
echo " " >> $outfile
echo "interface" >> $outfile
echo " " >> $outfile
echo "const" >> $outfile
echo "     VERSION       = '$major.$minor.$sub-$revision$release';" >> $outfile
echo "     VERSION_MAJOR = '$major';" >> $outfile
echo "     VERSION_MINOR = '$minor';" >> $outfile
echo "     VERSION_SUB   = '$sub';" >> $outfile
echo "     REVISION      = '$revision';" >> $outfile
echo "     RELEASE       = '$release';" >> $outfile
echo "     LINE_COUNT    = $linecount;" >> $outfile
echo " " >> $outfile
echo "implementation" >> $outfile
echo " " >> $outfile
echo "end." >> $outfile
