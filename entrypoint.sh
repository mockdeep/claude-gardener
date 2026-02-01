#!/bin/bash
set -e

# Mark GitHub workspace as safe for git operations
git config --global --add safe.directory /github/workspace
git config --global --add safe.directory "${GITHUB_WORKSPACE:-/github/workspace}"

# Run the main script
exec ruby /action/lib/claude_gardener.rb "$@"
