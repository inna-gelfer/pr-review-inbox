# pr-review-inbox 👀

A menu-bar badge for the gtforge PRs waiting on your review. Click one to review it in a
fresh Claude or Codex session.

- `👀 3` — how many are waiting; `👀 0` dimmed when nothing is.
- Each PR shows why it's there: `amended` (commits landed after your review), `answered`
  (no new code, but someone replied to you — a refusal to change still needs a decision),
  `unreviewed`, `tagged`
- **Review** opens a labelled tab in a dedicated **PR review** workspace — reused if it exists,
  created if it doesn't — starts your agent in the repo checkout, and submits `pr-review`
- **Skip until it changes** records the PR at its current head, so it stays out until new commits land — or until someone replies to you
- **Review with** switches between Claude and Codex — both run the same `cs-skills` review
- Merged and closed PRs drop off by themselves

## Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/inna-gelfer/pr-review-inbox/main/install.sh)"
```

Or clone and run `./install.sh`. Re-run it to upgrade; it keeps your agent choice.
Uninstall with `~/.pr-review-inbox/uninstall.sh`.

## Requirements

| | |
|---|---|
| macOS | required — Swift/Cocoa menu bar, launchd |
| Xcode command line tools | required to build (`xcode-select --install`) |
| `gh`, authenticated | required — the inbox is two `gh search` calls |
| the `pr-review-inbox` skill | required — this app displays its `candidates.py` output and nothing else |
| [herdr](https://herdr.dev) | optional — without it, Review opens a plain Ghostty window instead of a labelled tab |

The skill lives at `~/.claude/skills/pr-review-inbox/`; point elsewhere with
`PRI_CANDIDATES=/path/to/candidates.py ./install.sh`.

## How it refreshes

The search takes about 10 seconds, so it runs every 2 minutes in the background, and again
when you open the menu if the last one is over a minute old — the rows you're reading are the
last result until the new one lands. **Refresh now** forces it, and skipping a PR refreshes
immediately so the row disappears at once.

Reviewing a PR does *not* remove it — the review skill records it when it finishes. A
review you start and abandon comes back on the next poll, which is the point.

## What it touches

| Path | |
|---|---|
| `~/.pr-review-inbox/` | app, agent choice, cached inbox, `review.log` |
| herdr workspace `PR review` | where reviews open; rename via `workspace` in the app dir |
| `~/Library/LaunchAgents/com.pr-review-inbox.badge.plist` | keeps it running |

`reviewed.json` belongs to the skill; Skip writes to it through `candidates.py`, and
uninstalling leaves it alone.
