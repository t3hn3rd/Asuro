#!/bin/bash
echo "Generating Versioning Info..."
./checksum.sh
outfile="src/include/asuro.pas"
file="version"
while IFS=: read -r line;do
	major=$(echo $line | awk '{print $1}')
	minor=$(echo $line | awk '{print $2}')
	sub=$(echo $line | awk '{print $3}')
	release=$(echo $line | awk '{print $4}')
done <"$file"
linecount=$(./loc.sh | awk '{print $1}')
sourcecount=$(find src -type f | wc -l)
drivercount=$(find src/driver -type f | wc -l)
revision=$(git rev-list --count HEAD)
fpcversion=$(fpc -h | grep -m 1 version | awk '{print $5}')
makeversion=$(make -v | grep GNU | awk '{print $3}')
nasmversion=$(nasm -v | awk '{print $3'})
compiledate=$(date +"%d/%m/%y")
compiletime=$(date +"%T")
checksum=$(md5sum checksums.md5 | awk '{print $1}')
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
echo "     FILE_COUNT    = $sourcecount;" >> $outfile
echo "     DRIVER_COUNT  = $drivercount;" >> $outfile
echo "     FPC_VERSION   = '$fpcversion';" >> $outfile
echo "     NASM_VERSION  = '$nasmversion';" >> $outfile
echo "     MAKE_VERSION  = '$makeversion';" >> $outfile
echo "     COMPILE_DATE  = '$compiledate';" >> $outfile
echo "     COMPILE_TIME  = '$compiletime';" >> $outfile
echo "     CHECKSUM      = '$checksum';" >> $outfile
echo " " >> $outfile
echo "implementation" >> $outfile
echo " " >> $outfile
echo "end." >> $outfile
echo "Generating release info..."
wget -q https://img.shields.io/badge/version-$major.$minor.$sub--$revision$release-blue.svg -O release/version.svg
wget -q https://img.shields.io/badge/revision-$revision-blue.svg -O release/revision.svg
wget -q https://img.shields.io/badge/release-$release-blue.svg -O release/release.svg
wget -q https://img.shields.io/badge/lines-$linecount-blueviolet.svg -O release/lines.svg
wget -q https://img.shields.io/badge/files-$sourcecount-blueviolet.svg -O release/files.svg
wget -q https://img.shields.io/badge/drivers-$drivercount-blueviolet.svg -O release/drivers.svg
wget -q https://img.shields.io/badge/FPC_version-$fpcversion-lightgrey.svg -O release/fpcversion.svg
wget -q https://img.shields.io/badge/NASM_version-$nasmversion-lightgrey.svg -O release/nasmversion.svg
wget -q https://img.shields.io/badge/MAKE_version-$makeversion-lightgrey.svg -O release/makeversion.svg
wget -q https://img.shields.io/badge/release_date-$compiledate-lightgrey.svg -O release/date.svg
wget -q https://img.shields.io/badge/fingerprint-$checksum-important.svg -O release/fingerprint.svg
echo "Done versioning."
