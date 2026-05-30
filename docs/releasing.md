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
        │  release job:  builds <plugin-id>-X.Y.Z.plasmoid,
        │                 smoke-tests it, publishes a GitHub Release
        │  appimage job: builds Ring_Monitor-X.Y.Z-x86_64.AppImage,
        │                 attaches it to that same Release
        ▼
KDE Store upload (manual)
   https://www.opendesktop.org/p/2360410
```

So each tagged release carries **two artifacts**: the `.plasmoid` (for
KDE Plasma, also uploaded to the store) and the standalone AppImage (for
every other Linux desktop — issue #7). They split into two jobs so the
fast `.plasmoid` publish isn't coupled to the slower Qt + linuxdeploy
toolchain; the `appimage` job `needs: release` and uploads into the
Release the first job created (`gh release upload … --clobber`, so a
`workflow_dispatch` re-run is idempotent).

**AppImage build.** Driven by `scripts/build-appimage.sh` (the single
source of truth, also run by the `appimage` smoke-build job in
`ci.yml`): CMake `install()` rules stage an AppDir (binary + `.desktop`
+ icon from `packaging/`), then `linuxdeploy` + `linuxdeploy-plugin-qt`
bundle Qt and emit the AppImage. It runs on **ubuntu-22.04 (glibc
2.35)**, not the `fedora:41` container the C++ build job uses — a
Fedora-41 glibc (2.40) AppImage would refuse to start on older targets
(Linux Lite / Ubuntu 24.04). Ubuntu 22.04 ships Qt 6.2 (< the 6.5
`CMakeLists.txt` requires), so Qt 6.5 comes from `aqtinstall`. The CI
job additionally runs the bundled binary offscreen as a portability
smoke-test (exit 124 = the QML root loaded).

- `bump:major|minor|patch` → SemVer bump as expected.
- No `bump:*` label on the merged PR → `version.yml` exits cleanly, no
  tag, no release. Useful for tooling-only PRs.

**`metadata.json` `KPlugin.Version` is the single source of truth.**
`version.yml` bumps only that file. The standalone build does NOT
hardcode the version anywhere: `CMakeLists.txt` parses
`KPlugin.Version` out of `metadata.json` at configure time and feeds
it to both `project(VERSION …)` and the `RING_MONITOR_VERSION`
compile definition, which `standalone/main.cpp` passes to
`setApplicationVersion()` (→ `Qt.application.version` → the
standalone About tab's `localVersion`). Never reintroduce a literal
version string in `CMakeLists.txt` or `main.cpp` — it will drift
behind the pipeline (it did, sitting at `0.5.0` while the store/tags
moved on).

**Cadence: bump only at milestones.** Intermediate PRs (cleanup,
fix, refactor) ship with no `bump:*` label. Each bump cuts a GitHub
release ahead of the *manually-uploaded* KDE Store, and the widget's
update badge points users at the store — so a stream of intermediate
bumps leaves store users staring at a perpetual "update available"
that dead-ends on a store with nothing newer. Bump when you're ready
to also upload the store in the same pass.

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
   no-op PR (e.g. fix a typo) with the desired `bump:*` label. The
   bump is computed from `metadata.json`'s current value, so a
   missed `vN+1` jump can be recovered by labeling the recovery PR
   with the same `bump:*` level the missed PR carried.
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

**The upload step is manual** — and unavoidably so for now. The OCS
(Open Collaboration Services) API that opendesktop.org / Pling exposes
is read-only: write endpoints for content uploads have never been
shipped. Pling administrators confirmed this most recently in
[September 2023](https://forum.opendesktop.org/t/there-is-a-way-to-setup-a-continuous-deployment-from-a-app-in-pling/18876),
and the OCS API documentation page makes the same point. No GitHub
Action exists for this reason — the root cause is server-side.

What `.github/workflows/release.yml` does instead: enrich each GitHub
Release body with a **"KDE Store upload" helper block** containing the
direct download link, the version string, and a click-through to the
store entry. The manual procedure shrinks to three clicks:

1. Open the GitHub Release for the version (e.g.
   `https://github.com/manuacl/ring-monitor/releases/tag/vX.Y.Z`).
2. Download the `.plasmoid` from the assets, follow the link to
   `https://www.opendesktop.org/p/2360410`, log in, click **Edit**.
3. Upload the file, set version = `X.Y.Z`, paste the **What's
   Changed** section from the GitHub Release into the changelog field.
   Save.

If Pling ships write endpoints in the future, replace the "Compose
release body" step in `release.yml` with a real upload call. The
artifact path, version, and changelog are already computed there —
only the final POST changes.
