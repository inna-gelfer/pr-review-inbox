#!/bin/bash
# Installs the pr-review-inbox menu-bar badge.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
REPO="${PRI_REPO:-https://github.com/inna-gelfer/pr-review-inbox}"

# piped from curl: the sources aren't next to the script, so fetch them
if [ ! -f "$SRC/menubar.swift" ]; then
  SRC="$(mktemp -d)"
  echo "==> downloading"
  curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | tar xz -C "$SRC" --strip-components=1
fi

[ "$(uname)" = Darwin ] || { echo "macOS only"; exit 1; }
command -v swiftc >/dev/null || { echo "need the Xcode command line tools: xcode-select --install"; exit 1; }
command -v gh >/dev/null || { echo "need the GitHub CLI: brew install gh"; exit 1; }

DIR="$HOME/.pr-review-inbox"
mkdir -p "$DIR"
cp "$SRC/menubar.swift" "$SRC/uninstall.sh" "$DIR/"
chmod +x "$DIR/uninstall.sh"

# The inbox itself comes from the pr-review-inbox skill; this app only displays it.
CAND="${PRI_CANDIDATES:-$HOME/.claude/skills/pr-review-inbox/candidates.py}"
if [ ! -f "$CAND" ]; then
  echo "!! candidates.py not found at $CAND"
  echo "   install the pr-review-inbox skill, or set PRI_CANDIDATES and re-run"
  exit 1
fi
echo "$CAND" > "$DIR/candidates-path"
[ -f "$DIR/agent" ] || echo claude > "$DIR/agent"   # keep an existing choice

echo "==> building"
# Never compile over the running binary: replacing a mapped image invalidates its
# signature and macOS kills the app (OS_REASON_CODESIGNING).
swiftc -O -o "$DIR/pr-review-inbox.new" "$DIR/menubar.swift"
codesign --force --sign - "$DIR/pr-review-inbox.new" >/dev/null 2>&1 || true
mv -f "$DIR/pr-review-inbox.new" "$DIR/pr-review-inbox"

echo "==> starting"
mkdir -p "$HOME/Library/LaunchAgents"
PLIST="$HOME/Library/LaunchAgents/com.pr-review-inbox.badge.plist"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.pr-review-inbox.badge</string>
  <key>ProgramArguments</key><array><string>$DIR/pr-review-inbox</string></array>
  <!-- launchd hands over a minimal PATH, and candidates.py shells out to gh -->
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
PLISTEOF
# Always a full reload: kickstart would restart the binary but keep the loaded
# plist, so an edited environment or path would silently not take. bootout is
# async, hence the retry.
launchctl bootout "gui/$UID/com.pr-review-inbox.badge" 2>/dev/null || true
for _ in 1 2 3 4 5; do
  launchctl bootstrap "gui/$UID" "$PLIST" 2>/dev/null && break
  sleep 1
done

command -v herdr >/dev/null || echo "!! no herdr: reviews open a plain Ghostty window instead of a labelled tab"
echo "done — 👀 appears top right when something is waiting (first search takes ~10s)."
