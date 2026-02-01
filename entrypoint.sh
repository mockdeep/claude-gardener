#!/bin/bash
set -e

# Use gardener user's home (GitHub Actions sets HOME to /github/home which isn't writable)
export HOME=/home/gardener

# Mark GitHub workspace as safe for git operations
git config --global --add safe.directory /github/workspace
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/github/workspace}"

# Run the main script
exec ruby /action/lib/claude_gardener.rb "$@"
