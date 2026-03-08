#!/usr/bin/env bash
echo " "
echo "======================="
echo " "
echo "Generating Documentation..."
echo " "

if ! command -v mkdocs &> /dev/null; then
    echo "Installing mkdocs-material..."
    pip install --quiet "mkdocs>=1.6,<2" mkdocs-material
fi

echo "Building static site..."
mkdocs build --strict

if [ $? -eq 0 ]; then
    echo "Documentation built successfully. Output: site/"
else
    echo "Documentation build failed."
    exit 1
fi
