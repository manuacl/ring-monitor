---
name: repo-stats
description: Report GitHub traffic for manuacl/ring-monitor — page views, clones, referrers, top paths, and release download counts — plus the long-term archived history (beyond GitHub's 14-day window) from the `stats` branch. Crucially, it separates human interest from bot/CI noise. Use when the user asks "les stats du repo", "combien de visites/clones/téléchargements", "repo traffic", "who's looking at the repo".
user-invocable: true
---

# repo-stats — ring-monitor GitHub traffic

Pull and interpret the GitHub traffic for `manuacl/ring-monitor`. The hard part
is **not** fetching the numbers — it's reading them honestly. The clone count is
dominated by this repo's own CI (every `actions/checkout` is a clone), so a raw
"2500 clones" is meaningless without the bot correction.

## What to fetch

Run these with `gh` (resolve the repo with `gh repo view --json nameWithOwner`
in case the slug ever changes):

```bash
REPO=manuacl/ring-monitor
gh api repos/$REPO/traffic/views            # 14d: count + uniques, daily buckets
gh api repos/$REPO/traffic/clones           # 14d: count + uniques, daily buckets
gh api repos/$REPO/traffic/popular/referrers
gh api repos/$REPO/traffic/popular/paths
gh api repos/$REPO/releases \
  --jq '.[] | "\(.tag_name)\t\([.assets[].download_count] | add // 0)"'
```

The traffic endpoints need push access — they work for the maintainer's own
`gh` auth. If they 403, the auth lacks push rights; say so rather than guessing.

## The bot correction (do not skip this)

Clones are almost entirely CI checkouts, not humans. Always correlate the daily
clone buckets against CI runs for the same days before reporting:

```bash
SINCE=$(date -d '14 days ago' +%F)
gh api --paginate "repos/$REPO/actions/runs?per_page=100&created=>=$SINCE" \
  --jq '.workflow_runs[].created_at[0:10]' | sort | uniq -c
```

If the clone peaks land on the same days as the CI-run peaks (they do — e.g. a
~70-run day shows ~500 clones), state plainly that the clone figure is mechanical
CI traffic, **not** adoption. The honest signals of human interest are:

- **page-view uniques** (real people browsing),
- **release download counts** (people installing),
- **referrers** (where they came from — the KDE Store / opendesktop.org is the
  main external funnel).

Never present total clones as "people who cloned the repo".

## Long-term history (beyond 14 days)

GitHub purges traffic after 14 days. The `traffic-stats.yml` workflow archives a
daily snapshot to the **`stats` orphan branch** as two CSVs. Read them without
switching the working tree:

```bash
gh api repos/$REPO/contents/traffic.csv?ref=stats   --jq '.content' | base64 -d
gh api repos/$REPO/contents/downloads.csv?ref=stats --jq '.content' | base64 -d
```

- `traffic.csv` — `date,views,views_unique,clones,clones_unique,ci_runs`
  (the `ci_runs` column is the built-in bot correction — high clones + high
  ci_runs on the same date = bot traffic).
- `downloads.csv` — `date,downloads_total` (cumulative release downloads snapshot;
  diff two dates to get downloads gained over a period).

If a fetch 404s, the workflow hasn't run yet or the branch doesn't exist — report
the live 14-day window only and note the archive is empty.

## Report shape

Lead with the **human** signals (view uniques, downloads, referrers), then give
clones with the bot caveat, then offer the long-term trend if the archive exists.
Keep it tight — a small table per section, not a data dump. Match the user's
conversation language (the repo files are English-only, but the chat reply is not
a committed file, so French is fine if the user writes in French).
