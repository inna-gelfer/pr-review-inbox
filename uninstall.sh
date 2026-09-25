#!/bin/bash
set -uo pipefail
launchctl bootout "gui/$UID/com.pr-review-inbox.badge" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.pr-review-inbox.badge.plist"
rm -rf "$HOME/.pr-review-inbox"
echo "removed. The skill and its reviewed.json are untouched."
