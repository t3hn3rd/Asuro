find . -name '*.pas' | xargs wc -l | awk '/./{line=$0} END{print line}'
