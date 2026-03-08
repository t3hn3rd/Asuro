#!/usr/bin/env bash
set -e
TOOLCHAIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo " "
echo "======================="
echo " "
echo "Generating Versioning Info..."
echo " "
chmod +x "${TOOLCHAIN_DIR}/compile_checksum.sh"
"${TOOLCHAIN_DIR}/compile_checksum.sh"
outfile="src/core/core.version.pas"
file="toolchain/version"
{
	# this script requires semver tool
	wget -q https://raw.githubusercontent.com/fsaintjacques/semver-tool/master/src/semver -O bin/semver && chmod +x bin/semver
	export PATH="$(pwd)/bin:$PATH"
}
tagref=$(git describe --tags)
revision=$(git rev-parse --short=8 HEAD)
major=$(semver get major $tagref)
minor=$(semver get minor $tagref)
sub=$(semver get patch $tagref)
version=$(semver get release $tagref)
release=$(semver get prerel $tagref)
build=$(semver get build $tagref)
linecount=$("${TOOLCHAIN_DIR}/loc.sh" | awk '{print $1}')
sourcecount=$(find src -type f | wc -l)
drivercount=$(find src/driver -type f | wc -l)
fpcversion=$(fpc -h | grep -m 1 version | awk '{print $5}')
makeversion=$(make -v | grep GNU | awk '{print $3}' | grep -v GNU)
nasmversion=$(nasm -v | awk '{print $3'})
compiledate=$(date +"%d/%m/%y")
compiletime=$(date +"%T")
checksum=$(md5sum checksums.md5 | awk '{print $1}')

[[ -n "$release" ]] && version="$version-$release"
cat > $outfile <<EOF
unit core.version;
 
interface
 
const
     VERSION       = '$version';
     VERSION_MAJOR = '$major';
     VERSION_MINOR = '$minor';
     VERSION_SUB   = '$sub';
     REVISION      = '$revision';
     RELEASE       = '$release';
     LINE_COUNT    = $linecount;
     FILE_COUNT    = $sourcecount;
     DRIVER_COUNT  = $drivercount;
     FPC_VERSION   = '$fpcversion';
     NASM_VERSION  = '$nasmversion';
     MAKE_VERSION  = '$makeversion';
     COMPILE_DATE  = '$compiledate';
     COMPILE_TIME  = '$compiletime';
     CHECKSUM      = '$checksum';
 
implementation
 
end.
EOF
echo "Generating release info..."
set +e # These can fail on branches and such, for now
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
