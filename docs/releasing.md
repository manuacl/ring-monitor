# Releasing

How a merged PR becomes a released version of the widget.

## Flow overview

```
PR merged with bump:* label
        │
        ▼
.github/workflows/version.yml
        │  bumps metadata.json → KPlugin.Version
        │  commits "chore: bump version to X.Y.Z (<type>)"
        │  tags vX.Y.Z
        │  pushes both to main
        ▼
.github/workflows/release.yml
        │  builds <plugin-id>-X.Y.Z.plasmoid
        │  smoke-tests the package
        │  publishes a GitHub Release with auto-generated notes
        ▼
KDE Store upload (manual)
   https://www.opendesktop.org/p/2360410
```

- `bump:major|minor|patch` → SemVer bump as expected.
- No `bump:*` label on the merged PR → `version.yml` exits cleanly, no
  tag, no release. Useful for tooling-only PRs.

The `bump:*` label is applied at PR-creation time by the
`bump-label` skill (auto-picked from commit subjects). Override with
`gh pr edit <n> --remove-label bump:X --add-label bump:Y` if needed.

## The `BUMP_TOKEN` secret

`.github/workflows/version.yml` pushes the bump commit and the tag
directly to `main`. The default `GITHUB_TOKEN` runs as
`github-actions[bot]`, which has no bypass for the repository's
branch-protection ruleset → those pushes are rejected.

To unblock, the workflow uses a **`BUMP_TOKEN` repository secret**: a
Personal Access Token (classic) owned by an admin user, scope `repo`
only. The admin's `RepositoryRole id=5` is in the ruleset's bypass
actors list, so the push succeeds while every human (including the
admin via the GitHub UI) still goes through the normal PR + CI flow.

### Rotation

The token's expiration is set to 90 days by convention. When it
expires:

1. Generate a new PAT: https://github.com/settings/tokens →
   *Generate new token (classic)* → name `ring-monitor bump bot`,
   scope `repo`, expiration 90 days.
2. Update the secret:
   https://github.com/manuacl/ring-monitor/settings/secrets/actions →
   click `BUMP_TOKEN` → *Update secret* → paste the new token.
3. Revoke the old one in the PATs page (cleanup).

`version.yml` will fail loudly the first time it runs with an expired
token — the error is unambiguous (`401 Bad credentials` on the push),
no silent broken state.

### Risk profile

A `repo`-scoped PAT can do anything the user can do on the user's
repositories. The mitigations:

- Lives only in encrypted GitHub repository secrets — never logged,
  never echoed by workflows.
- Repository is single-maintainer; no other actor reads/writes
  secrets.
- 90-day expiration limits the window if the token ever leaks
  (accidental paste, screenshot, etc.).
- Scope is `repo` only, not `admin:org` or `delete_repo`.

## Manual release for a missed tag

If `version.yml` ran but the tag wasn't pushed (e.g. before
`BUMP_TOKEN` was set up), the tag is missing on the remote. Two
recovery paths:

1. **Trigger a fresh release via a tiny PR** — open a one-line
   no-op PR (e.g. fix a typo) with the desired `bump:*` label.
   `version.yml` will bump from the current `metadata.json` baseline,
   not from where it would have been.
2. **Manual bump locally** — `jq` the metadata.json, commit on a
   branch, open a PR, merge it with the `bump:*` label.

Either way, once the tag exists, `release.yml` runs automatically. If
`release.yml` did not run (e.g. tag was pushed before it landed on
main), trigger it manually:

```
gh workflow run release.yml --field tag=v0.2.0
```

## KDE Store

The widget is published at https://www.opendesktop.org/p/2360410.
Upload is manual for now: download the `.plasmoid` artifact from the
GitHub Release, then upload it via the store's web UI. Automating this
via the OCS API is deferred.
