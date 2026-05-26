---
name: finish-branch
description: Audit a ring-monitor branch (CLAUDE.md rules, pre-commit, CI) THEN push and open the PR if everything is green. Trigger when the user says "finis la branche", "prêt à merger ?", "/finish-branch", "ouvre la PR".
---

# Finish branch — ring-monitor

Full "branch → opened PR" pipeline:

1. Local audit (CLAUDE.md rules + pre-commit + CI reproduced).
2. If **everything is green**: push + `gh pr create`.
3. If **any check is red**: stop, do not push, report what needs fixing.

The goal is **zero surprise** when the pipeline runs and **zero PR
opened on red**.

## When to use

- The user says "finis la branche", "prêt à merger ?", "audit branche",
  invokes `/finish-branch`, or asks to open a PR.
- Before a `git push` on an open PR (or before opening one).
- After a large refactor session, to ensure no rule was broken on the
  way.

## When NOT to use

- To validate a visual UI fix → prefer `refresh-widget` + human eye.
- For a WIP commit that will be squashed later — this skill audits the
  final state, not each intermediate step.

## Procedure

**Phase A — audit + reflection**: run checks 1 → 6 in order. Checks
1-5 are mechanical (pre-commit / CI / CLAUDE.md rules / docs / git
state); check 6 is a forward-looking reflection on whether anything
we learned warrants a new `CLAUDE.md` rule. Stop at the first block
that surfaces red — the user prefers fixing one layer at a time
rather than receiving a tsunami of findings. For each block, report
PASS / FAIL with useful details.

**Phase B — push + PR + version tag**: only fire if phase A is fully
green. Steps 7 (push + open PR) and 8 (recommend & apply `bump:X`
label) run back-to-back.

### 1. Pre-commit — file-size + qmllint + qmlformat

Reproduces `.githooks/pre-commit` without depending on staging (audits
the full working tree).

```bash
# 1a. 500-line cap on source + tests.
MAX=500
status=0
shopt -s nullglob
for f in contents/ui/*.qml contents/ui/*.js \
         contents/ui/core/*.qml contents/ui/core/*.js \
         contents/ui/platforms/plasma/*.qml \
         contents/ui/platforms/standalone/*.qml \
         standalone/*.cpp \
         tests/*.test.mjs tests/qml/*.qml; do
    lines=$(wc -l < "$f")
    if [ "$lines" -gt "$MAX" ]; then
        echo "FAIL: $f = $lines lines (> $MAX)"
        status=1
    fi
done
[ $status -eq 0 ] && echo "PASS: file-size (≤500 lines)"

# 1b. qmlformat no-op on source .qml files.
for f in contents/ui/*.qml contents/ui/core/*.qml contents/ui/platforms/plasma/*.qml contents/ui/platforms/standalone/*.qml; do
    if ! diff -q "$f" <(qmlformat-qt6 "$f") > /dev/null; then
        echo "FAIL: $f is not qmlformat-clean"
        echo "  fix: qmlformat-qt6 --inplace $f"
        status=1
    fi
done

# 1c. qmllint on source + QML tests.
qmllint-qt6 contents/ui/*.qml contents/ui/core/*.qml contents/ui/platforms/plasma/*.qml contents/ui/platforms/standalone/*.qml tests/qml/*.qml || status=1

# 1d. Plasma-isolation invariant: nothing under contents/ui/core/ may
# import any org.kde.* module except org.kde.kirigami. The standalone
# port (issue #7) drops in a sibling platforms/standalone/ and reuses core/
# verbatim. See docs/plasma-isolation/plan.md and CLAUDE.md
# § Working rules.
#
# Allowlist (not denylist): Kirigami is a KF6 framework that runs on
# any Qt 6 desktop, and a standalone build can ship it as a runtime
# dep — that's why PR 5 (FormLayout helper) was skipped. Anything
# else under org.kde.* (kquickcontrols, plasma.*, kcmutils,
# ksysguard.*, kcoreaddons, kio, …) is Plasma- or KDE-host-bound and
# must live behind an adapter in contents/ui/platforms/plasma/.
forbidden=$(grep -rnE 'import org\.kde\.' contents/ui/core/ 2>/dev/null | \
    grep -vE 'import org\.kde\.kirigami($|[[:space:]])')
if [ -n "$forbidden" ]; then
    echo "$forbidden"
    echo "FAIL: contents/ui/core/ imports a non-Kirigami org.kde.* module (plasma-isolation invariant)"
    echo "  fix option A: if the wrapped type is Kirigami-only, drop the adapter and import Kirigami directly"
    echo "       (DraggableList swapped Platform.ThemedIcon → Kirigami.Icon this way in PR #32)"
    echo "  fix option B: take the platform-specific Component as a property injected by the wrapper"
    echo "       (AppearanceBody.colorPickerComponent — Plasma wrapper + standalone SettingsDialog each pass their own)"
    status=1
else
    echo "PASS: plasma-isolation invariant (core/ has no non-Kirigami org.kde.* imports)"
fi

# 1d-bis. Path-based platform isolation: nothing in contents/ui/core/
# may import a sibling platforms/* directory by relative path. The
# `org.kde.*` check above catches the Plasma-namespace import; this
# catches the "core/ → ../platforms/<X>" path import that hardcodes
# core/ to ONE platform and silently breaks the standalone build at
# runtime (the standalone adapter folder is not on its qrc:// path
# even though it physically exists in the source tree).
#
# Found in PR #32 (PR F2): DraggableList.qml + AppearanceBody.qml both
# imported "../platforms/plasma" — the standalone binary failed to
# load with `qrc:/.../platforms/plasma: no such directory`. The two
# fix patterns are listed in the PASS message above.
path_forbidden=$(grep -rnE 'import "\.\./platforms/' contents/ui/core/ 2>/dev/null)
if [ -n "$path_forbidden" ]; then
    echo "$path_forbidden"
    echo "FAIL: contents/ui/core/ imports a sibling platforms/* directory by relative path (platform-isolation invariant)"
    echo "  fix: same two patterns as 1d above (Kirigami-direct OR Component-injection via wrapper)"
    status=1
else
    echo "PASS: path-isolation (core/ does not import sibling platforms/* directories)"
fi
```

### 2. CI — Node tests + QML tests

```bash
# 2a. Node tests (pure logic).
node --test tests/*.test.mjs

# 2b. QML tests (qmltestrunner headless, like CI).
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input tests/qml
```

### 3. CLAUDE.md rules not covered by pre-commit/CI

These rules live in `CLAUDE.md` § "Working rules" but have no mechanical
equivalent in the pipeline — check them here.

**3a. Every `.js` module has its paired test file.**

```bash
for js in contents/ui/core/*.js; do
    base=$(basename "$js" .js)
    # Convention: CamelCase.js → kebab-case.test.mjs
    # (see RingGeometry.js → ring-geometry.test.mjs)
    kebab=$(echo "$base" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]')
    test_file="tests/${kebab}.test.mjs"
    if [ ! -f "$test_file" ]; then
        echo "FAIL: $js has no paired test ($test_file missing)"
        status=1
    fi
done
```

**3b. No nested ternaries in source/tests.**

Heuristic: a line with two `?` and two `:` is suspect. False positives
possible (e.g. `foo ? 'a:b' : 'c'`) — re-read each match.

```bash
grep -nE '\?[^?]*\?[^:]*:[^:]*:' \
    contents/ui/*.qml contents/ui/*.js \
    contents/ui/core/*.qml contents/ui/core/*.js \
    contents/ui/platforms/plasma/*.qml \
    contents/ui/platforms/standalone/*.qml \
    standalone/*.cpp \
    tests/*.test.mjs tests/qml/*.qml \
    2>/dev/null && echo "FAIL: possibly nested ternaries (re-read matches)"
```

**3c. No `Plasmoid.configuration` read in a leaf component.**

DIP rule from the SOLID grid (CLAUDE.md). Leaves take props + emit
signals; wiring lives in the parent.

```bash
# Known leaf files today: everything under contents/ui/core/. The
# legitimate Plasmoid.configuration readers are platforms/plasma/ConfigStore.qml
# and the top-level wrappers (main.qml, configMetrics.qml,
# configAppearance.qml).
for f in contents/ui/core/*.qml; do
    if grep -n "Plasmoid\.configuration" "$f"; then
        echo "FAIL: $f reads Plasmoid.configuration (DIP violation — read it through configStore prop)"
        status=1
    fi
done
```

### 4. Tests & docs consistent with the branch diff — auto-create missing ones

The `origin/main..HEAD` diff must come with the tests and docs it
implies. A feature without a test or a module without a `docs/` entry
rarely merges on ring-monitor (see CLAUDE.md § Working rules: *"All
logic must be tested"* + *"Tests cover rendering too"*).

**Posture**: when a missing test or doc entry is detected, **create a
stub** rather than blocking — the user can flesh it out before
committing. Each auto-created file/entry should be reported in the
phase-A summary so nothing slips silently into the PR. A stub is
better than nothing: it makes the rule visible at commit time and
gives the user a place to start. Do not invent assertions for code
you haven't read carefully; the stub should be obviously a stub
(comment, `TODO`, one trivial assertion).

```bash
# Files touched by the branch.
changed=$(git diff --name-only origin/main...HEAD)
echo "$changed"

# 4a. Every modified or added .js must have its .test.mjs touched too.
for js in $(echo "$changed" | grep '^contents/ui/\(core/\)\?.*\.js$'); do
    base=$(basename "$js" .js)
    kebab=$(echo "$base" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr '[:upper:]' '[:lower:]')
    test_file="tests/${kebab}.test.mjs"
    if ! echo "$changed" | grep -qx "$test_file"; then
        echo "WARN: $js modified without touching $test_file"
        echo "  → is the test still relevant? is a case missing?"
    fi
done

# 4b. New .qml component (= new file under contents/ui) → auto-create
# tst_<Name>.qml stub if missing (cf. tests/qml/tst_Ring.qml,
# tst_MetricRow.qml, tst_DraggableList.qml).
for qml in $(git diff --name-only --diff-filter=A origin/main...HEAD | grep '^contents/ui/\(core/\|platforms/plasma/\|platforms/standalone/\)\?.*\.qml$'); do
    base=$(basename "$qml" .qml)
    # Exclude top-level wrappers + Main.qml (entry points, not
    # reusable components → no tst_*.qml expected).
    case "$base" in main|Main|configMetrics|configAppearance|configGeneral) continue ;; esac
    test_file="tests/qml/tst_${base}.qml"
    if [ ! -f "$test_file" ]; then
        echo "CREATE: $test_file (stub)"
        # Use the Write tool to scaffold the file with: QtTest import,
        # TestCase named after the component, one `test_smoke` that
        # instantiates the component and asserts it loads. Mark the
        # body with `// TODO: add real assertions` so the user sees it.
        # The import path is "../../contents/ui/core" for core/ files,
        # "../../contents/ui/platforms/plasma" for Plasma adapters,
        # "../../contents/ui/platforms/standalone" for standalone adapters.
    fi
done

# 4c. New logic module (.js) → add a stub entry in docs/logic-modules.md
# if missing.
for js in $(git diff --name-only --diff-filter=A origin/main...HEAD | grep '^contents/ui/\(core/\)\?.*\.js$'); do
    base=$(basename "$js" .js)
    if ! grep -q "$base" docs/logic-modules.md 2>/dev/null; then
        echo "CREATE: docs/logic-modules.md entry for $base (stub)"
        # Use Edit to append a section: `## $base` + one-line TODO
        # placeholder describing what to document (purpose, public API).
    fi
done

# 4d. New component (.qml) → add a stub entry in docs/components.md
# if missing.
for qml in $(git diff --name-only --diff-filter=A origin/main...HEAD | grep '^contents/ui/\(core/\|platforms/plasma/\|platforms/standalone/\)\?.*\.qml$'); do
    base=$(basename "$qml" .qml)
    case "$base" in main|Main|configMetrics|configAppearance|configGeneral) continue ;; esac
    if ! grep -q "$base" docs/components.md 2>/dev/null; then
        echo "CREATE: docs/components.md entry for $base (stub)"
        # Same shape: `## $base` + TODO line.
    fi
done

# 4e. New key in contents/config/main.xml → mention in docs/
# config-dialog.md. If neither docs/ nor docs/config-dialog.md was
# touched, append a TODO stub there.
if git diff --name-only origin/main...HEAD | grep -q '^contents/config/main.xml$'; then
    docs_touched=$(echo "$changed" | grep '^docs/' | head -1)
    if [ -z "$docs_touched" ]; then
        echo "CREATE: docs/config-dialog.md TODO note (stub)"
        # Append a one-liner: "TODO: document new config key(s) added in
        # this branch — see contents/config/main.xml."
    fi
fi

# 4f. Modified (not just added) .qml that gained new public properties
# → docs/components.md must be touched AND the component's section
# should appear in the docs diff. Catches the failure mode where an
# existing leaf gets new theme tokens / API and the docs go stale.
# Excludes platforms/plasma/ (adapters), main.qml, config* (parent shells).
for qml in $(echo "$changed" | grep '^contents/ui/\(core/\)\?.*\.qml$' | grep -v '^contents/ui/platforms/plasma/'); do
    base=$(basename "$qml" .qml)
    case "$base" in main|configMetrics|configAppearance|configGeneral) continue ;; esac
    # Was it modified (not added)? Added files are handled by 4d.
    if ! git diff --name-only --diff-filter=M origin/main...HEAD | grep -qx "$qml"; then
        continue
    fi
    # Count NEW property declarations in the diff.
    added_props=$(git diff origin/main...HEAD -- "$qml" | grep -cE '^\+[[:space:]]+property[[:space:]]+')
    if [ "$added_props" -gt 0 ]; then
        if ! echo "$changed" | grep -qx "docs/components.md"; then
            echo "FAIL: $qml added $added_props new property declaration(s) but docs/components.md was not touched"
            status=1
        elif ! git diff origin/main...HEAD -- docs/components.md | grep -q "$base"; then
            echo "WARN: $qml added $added_props new property declaration(s); docs/components.md was touched but its $base section diff does not mention the component name"
            echo "  → did you update the right section?"
        fi
    fi
done

# 4g. New directory under contents/ui/ → must be mentioned in
# docs/architecture.md (file-layout tree). Catches structural moves
# (e.g. the core/ + platforms/plasma/ adapter split) that the architecture
# doc would otherwise miss. Compares against `git ls-tree origin/main`
# to skip directories that already existed (adding a new file inside
# an existing dir is not a structural change).
candidate_dirs=$(git diff --name-only --diff-filter=A origin/main...HEAD | \
    grep -oE '^contents/ui/[^/]+/' | sort -u | sed 's|/$||')
existing_dirs=$(git ls-tree -d --name-only -r origin/main contents/ui/ 2>/dev/null)
for d in $candidate_dirs; do
    if echo "$existing_dirs" | grep -qx "$d"; then
        continue  # dir already existed on main, not a structural change
    fi
    dname=$(basename "$d")
    if ! git diff origin/main...HEAD -- docs/architecture.md | grep -q "$dname"; then
        echo "FAIL: new directory $d not mentioned in docs/architecture.md (file layout tree)"
        status=1
    fi
done

# 4h. Manual audit prompt — these can't be greped reliably. Always
# print, so the user sees the checklist before phase B.
echo ""
echo "AUDIT (manual, did you also update if relevant?):"
echo "  - CLAUDE.md 'Where to look' if a new doc file lives outside the listed ones"
echo "  - Existing usage examples in docs/ that may reference an obsolete API"
echo "  - docs/adding-a-metric.md if a new metric or sensor pattern was introduced"
echo "  - docs/testing.md if a new test layout / runner / pattern was introduced"
```

**Stub shapes** (what the Write/Edit tool should produce):

- `tests/qml/tst_<Name>.qml` (pick the right subdir for `App`):
  ```qml
  import QtQuick
  import QtTest
  import "../../contents/ui/core" as App     // or "../../contents/ui/platforms/plasma"

  TestCase {
      name: "<Name>"

      App.<Name> { id: subject }

      function test_smoke() {
          verify(subject); // TODO: add real assertions
      }
  }
  ```

- `docs/logic-modules.md` / `docs/components.md` entry:
  ```markdown

  ## <Name>

  TODO: describe purpose + public API.
  ```

- `docs/config-dialog.md` note (appended):
  ```markdown

  > TODO: document new config key(s) — see `contents/config/main.xml`.
  ```

After creating any stub, **stage it** (`git add`) so it lands in the
same commit as the code that triggered it. Report each created path in
the phase-A summary with the `±` marker (see "Expected report") so the
user can decide whether to flesh it out now or commit-and-iterate.

### 5. Git state — blocking this time

Three conditions must hold to enter phase B:

```bash
# 5a. Clean working tree (otherwise these files get left behind).
git status --short
# Must be empty. If not → "FAIL: uncommitted changes, commit or stash
# before opening the PR" and stop.

# 5b. We are not on main.
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "main" ] && echo "FAIL: HEAD is on main, no PR possible" && exit 1

# 5c. Branch up to date with origin/main (rebase if needed).
git fetch origin main --quiet
behind=$(git rev-list --count HEAD..origin/main)
[ "$behind" -gt 0 ] && echo "FAIL: branch behind origin/main by $behind commit(s) — rebase first" && exit 1
```

### 6. CLAUDE.md lessons reflection — last thing before push

Look back over the branch and surface 0–3 candidate additions to
`CLAUDE.md`. Then ask the user verbatim:

> Est-ce que tu vois des règles à rajouter dans CLAUDE.md en
> fonction de ce qu'on a fait dans cette branche ?

**What is worth a rule:**

- An API choice that was non-obvious and cost an iteration to find
  (e.g. `Qt.styleHints.colorScheme` as the canonical KDE light/dark
  signal, after a failed luminance-probe attempt — added by PR #20)
- A platform-specific quirk a future contributor will hit cold (KDE
  bug numbers, plasmashell behaviour, qmllint quirks)
- A code pattern that emerged and should be the canonical way
  (e.g. the Plasma isolation seam invariant, added by PR #19)

**What is NOT worth a rule:**

- A one-off bug fix already obvious from the diff
- Code-specific details already commented in-situ
- Anything specific to this branch's feature alone — that goes in
  `docs/`, not `CLAUDE.md`

**Where in CLAUDE.md the addition lands:**

- "Common pitfalls (quick reminders)" for gotchas
- "Stack reminder" for QML/React mapping rows
- "Working rules" for project-wide constraints

Keep additions concise — `CLAUDE.md` is scanned, not read. Cite the
file where the canonical pattern lives so the rule is a pointer,
not a re-implementation of the pattern.

If the user accepts additions: write the edits, create a separate
`docs:` commit (so the rule is reviewable on its own), then loop
back through phase A on the new commit before moving to phase B —
pre-commit could legitimately fail on the new content.

If the user declines or there is nothing to add: proceed to step 7.

### 7. Push + open the PR (phase B)

**Only run if 1 → 6 are all green.**

```bash
# 7a. Gather context for drafting the PR.
git log --oneline origin/main..HEAD              # included commits
git diff origin/main...HEAD --stat               # change scope
gh pr view --json url 2>/dev/null && \
    echo "PR already open — push only, no re-create"
```

Build the PR title + body from the commits **and the diff** (not just
the latest commit). Follow the repo style (`git log` recent history for
message format — `feat:`, `fix:`, `docs:`, `chore:`, etc.).

```bash
# 7b. Push the branch (with -u if never pushed).
git push -u origin HEAD

# 7c. If a PR already exists, skip the create step — the push was
# enough to update it. Capture the PR number either way for step 8.
if pr_url=$(gh pr view --json url --jq .url 2>/dev/null); then
    pr_number=$(gh pr view --json number --jq .number)
else
    # 7d. Otherwise, open the PR. Title < 70 chars, body via HEREDOC.
    gh pr create --title "<concise title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullets: what the PR changes and why>

## Test plan
- [x] file-size cap (≤500 lines)
- [x] qmlformat no-op
- [x] qmllint (exit 0)
- [x] plasma-isolation invariant (`core/` has no non-Kirigami `org.kde.*` imports)
- [x] path-isolation (`core/` does not import sibling `platforms/*` directories)
- [x] `node --test` (<N/N>)
- [x] `qmltestrunner-qt6` headless (<N/N>)
- [x] `.js` modules / tests paired
- [x] No nested ternaries
- [x] DIP (leaves don't read `Plasmoid.configuration`)
- [x] Tests & docs consistent with diff
- [ ] <visual check if UI: refresh-widget + eye>

(Decompose the phase-A checks into individual bullets — each one
already ran locally, so they go in as `[x]`. The merger then sees
exactly which guard-rails passed, not just "finish-branch green".
Skip any bullet that's not relevant — e.g. drop the qmltestrunner
line if no `tests/qml/*.qml` exists. Do NOT list "CI green": all CI
checks are mandatory on this repo, the merge button enforces it,
listing it adds noise.)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
    pr_url=$(gh pr view --json url --jq .url)
    pr_number=$(gh pr view --json number --jq .number)
fi
echo "PR: $pr_url (#$pr_number)"
```

### 8. Version bump label — delegate to `bump-label` skill

Hand off to the project-bundled `bump-label` skill
(`.claude/skills/bump-label/`), which owns the convention
(`bump:major|minor|patch`, no label = no bump) and the heuristic. The
skill applies the recommended label directly, no confirmation prompt
— the user can swap it after the fact with one `gh pr edit` if they
disagree. Splitting it out keeps step 8 thin and lets contributors
invoke `bump-label` standalone (e.g. on a PR opened by hand, without
going through the full `finish-branch` audit).

Inputs to pass to `bump-label`:

- `pr_number`: captured at step 7.
- `current_version`: `jq -r .KPlugin.Version metadata.json`
- `changed_files`: `git diff --name-only origin/main...HEAD`
- `commits`: `git log --format='%B' origin/main..HEAD`

The label is consumed by `.github/workflows/version.yml`: on merge to
main, it reads the PR's `bump:*` label, bumps `metadata.json` →
`KPlugin.Version` accordingly, commits the change, and tags
`vX.Y.Z`. If no `bump:*` label is present, the workflow exits cleanly
without touching anything (matches the `bump-label` skill's "no label =
no bump" default).

Return the PR URL **and** the chosen bump level (or "no bump") to the
user.

### 9. Code review — invoke `/code-review`

Final step: hand the freshly-opened PR to Claude Code's built-in
`/code-review` command for a multi-agent cloud review. Phase A only
catches the mechanical rules (file size, qmllint, tests, plasma
isolation, doc consistency) — `/code-review` is where deeper feedback
(design smells, edge cases, security, naming) lands. Running it as
the last finish-branch step keeps the user's review loop tight: phase
A green → push → PR open → labelled → review feedback all in one
flow, instead of having to remember to fire `/code-review` separately.

```bash
# Invoke from the user's prompt (not from a sub-tool — the slash
# command is interpreted by the Claude Code client itself). Report:
#   "Now run: /code-review <pr_number>"
# so the user can press enter to fire it. Do NOT try to shell out
# `claude /code-review` — the command isn't exposed at the CLI.
```

If `/code-review` is unavailable in the user's environment (older
Claude Code, missing entitlements), say so and skip — don't block the
finish-branch flow on it. The PR is already opened and labelled;
reviews can happen async.

## Expected report

Summary table at the end of phase A:

```
✓ file-size (≤500 lines)
✓ qmlformat no-op
✓ qmllint
✓ plasma-isolation invariant (core/ has no non-Kirigami org.kde.* imports)
✓ node --test
✓ qmltestrunner
✓ .js modules / tests paired
⚠ ternaries: 1 match to re-read (ReorderLogic.js:42)
✓ DIP (leaves don't read Plasmoid.configuration)
± tests & docs: auto-created tests/qml/tst_Foo.qml stub
± tests & docs: auto-added docs/components.md entry for Foo
✗ tests & docs: Ring.qml added 2 properties but docs/components.md not touched
✗ tests & docs: new directory contents/ui/platforms/plasma/ not mentioned in architecture.md
↻ AUDIT printed — verify manually before phase B
✓ git: clean working tree, up to date with origin/main
```

The `±` marker means "auto-fixed — review before pushing". A run with
only ✓ and `±` is OK to push; the user should still scan each `±` line
to decide whether to flesh out the stub now or commit as-is and iterate.

- **All green** → chain into phase B (push + `gh pr create` + bump
  label), then return the PR URL and the chosen bump: "PR opened:
  <url> (tagged bump:minor)".
- **Any FAIL** → **do not push, do not create a PR**. Cite the
  file:line, suggest the precise fix (e.g. `qmlformat-qt6 --inplace
  contents/ui/Foo.qml`), do not apply the fix automatically — let the
  user validate.
- **Findings 3b/4 marked ⚠**: these are heuristics, the user decides
  **before** phase B runs — ask for confirmation if any are present.

## Why this procedure

- **Reproducing pre-commit + CI locally** avoids the push → CI red →
  fix → repush round-trip. On ring-monitor the pipeline is fast, but
  the user values the "only push green" discipline.
- **Also auditing non-mechanical rules**: `CLAUDE.md` § "Working
  rules" and § "Design principles" carry constraints (logic in tested
  `.js`, DIP on leaves) that drift silently if no one checks — that's
  exactly this skill's role before a merge.
- **Stopping at the first red block** avoids drowning the user; the
  next block may depend on the previous one (e.g. QML tests failing
  because qmllint rejected a file).

Rule details in `CLAUDE.md` (root) and check details in
`.githooks/pre-commit` + `.github/workflows/ci.yml`.
