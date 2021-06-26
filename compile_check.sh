#/bin/sh
echo " "
echo "======================="
echo " "
if [ "$1" = "failed" ]
then
	echo "Errors Occurred, please review."
	wget -q https://img.shields.io/badge/build-failed-red.svg -O release/build.svg 2>/dev/null
    echo " "
    echo "======================="
    exit 1
fi