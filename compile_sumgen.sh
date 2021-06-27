#/bin/sh
echo " "
echo "======================="
echo " "
echo "Generating Checksum Badge..."
echo " "
checksum=$(md5sum Asuro.iso | awk '{print $1}')
wget -q https://img.shields.io/badge/checksum-$checksum-important.svg -O release/checksum.svg 2>/dev/null