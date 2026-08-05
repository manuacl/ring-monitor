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

## KDE Store downloads — the dominant channel (don't skip)

The GitHub Releases counter only covers AppImage / standalone grabs + the dev's
own checkouts. The **Plasma widget installs from the KDE Store**, a channel
GitHub traffic is completely blind to. Measured 2026-06-02: store ≈ **334**
downloads vs GitHub Releases **34** — the store is ~10× larger and is the real
adoption signal. Always pull it; reporting GitHub downloads alone undercounts
installs by an order of magnitude.

The product is `https://www.opendesktop.org/p/2360410` (id **2360410**, also
mirrored at `store.kde.org` / `api.kde-look.org`). Two endpoints, no auth:

```bash
PID=2360410
# Product metadata. NOTE: the `downloads` field here is NOT the cumulative
# total — it undercounts badly (showed 69 when the real sum was 334). Use it
# only for name / current version / score, never as the download total.
curl -fsS "https://api.opendesktop.org/ocs/v1/content/data/$PID?format=json"

# Per-file counts INCLUDING archived/de-listed versions. This is the source
# of truth for downloads. `files[].downloaded_count_uk` is the per-file count;
# `active=="1"` flags the currently-listed files, archived ones are `"0"`.
curl -fsS "https://www.opendesktop.org/p/$PID/loadFiles" -o /tmp/files.json
python3 - <<'PY'
import json
files = json.load(open("/tmp/files.json"))["files"]
tot = 0
for f in sorted(files, key=lambda x: x.get("created_timestamp", "")):
    dl = int(f.get("downloaded_count_uk") or 0); tot += dl
    flag = "active" if f.get("active") == "1" else "arch"
    print(f"{str(f.get('version')):10} {flag:6} {dl:>5}  {f.get('name')}")
print("TOTAL store downloads =", tot)
PY
```

The **true cumulative store total is the sum of `downloaded_count_uk` across all
files** (active + archived), not the OCS `downloads` field. Watch for re-uploads:
a version can appear twice (an archived `0`-download entry + the live one, or a
`-<timestamp>` dupe) — sum them all, they're real distinct files.

`loadFiles` is on the `www.opendesktop.org` host specifically (the `www.pling.com`
host 301-redirects to it; follow the redirect or hit opendesktop directly).

## Report shape

Lead with the **KDE Store download total** (the real install signal) and the
GitHub **human** signals (view uniques, release downloads, referrers), then give
clones with the bot caveat, then offer the long-term trend if the archive exists.
Keep it tight — a small table per section, not a data dump. Match the user's
conversation language (the repo files are English-only, but the chat reply is not
a committed file, so French is fine if the user writes in French).
