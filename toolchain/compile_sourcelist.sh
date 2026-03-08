#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Generating Source List..."
echo " "
find "$(cd ..; pwd)" -name "*.pas" > sources.list
echo "Finished Source List Generation."
exit 0