#!/bin/sh

# ci_post_clone.sh
# This script runs after Xcode Cloud clones the repository

set -e

echo "Post-clone script started"

# Ensure we're using the latest version of Xcode command line tools
xcode-select --print-path

echo "Post-clone script completed"
