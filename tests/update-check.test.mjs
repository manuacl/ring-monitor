// Tests for UpdateCheck.js — the pure semver + notification gating logic
// behind the in-widget "update available" badge.

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const UC = require("../contents/ui/core/UpdateCheck.js");

// ── parseSemver ────────────────────────────────────────────────────────

test("parseSemver: accepts a leading v", () => {
    assert.deepEqual(UC.parseSemver("v0.4.0"), [0, 4, 0]);
});

test("parseSemver: accepts a plain X.Y.Z", () => {
    assert.deepEqual(UC.parseSemver("1.2.3"), [1, 2, 3]);
});

test("parseSemver: ignores a pre-release / build suffix", () => {
    // GitHub release tags sometimes carry an -rc1, +build, etc.
    assert.deepEqual(UC.parseSemver("v0.4.0-rc1"), [0, 4, 0]);
    assert.deepEqual(UC.parseSemver("0.4.0+build42"), [0, 4, 0]);
});

test("parseSemver: malformed input returns null", () => {
    assert.equal(UC.parseSemver(""), null);
    assert.equal(UC.parseSemver("v0.4"), null);
    assert.equal(UC.parseSemver("garbage"), null);
    assert.equal(UC.parseSemver(null), null);
    assert.equal(UC.parseSemver(undefined), null);
    assert.equal(UC.parseSemver(42), null);
});

// ── compareSemver ──────────────────────────────────────────────────────

test("compareSemver: equal versions → 0", () => {
    assert.equal(UC.compareSemver([0, 4, 0], [0, 4, 0]), 0);
});

test("compareSemver: major dominates minor and patch", () => {
    assert.equal(UC.compareSemver([1, 0, 0], [0, 9, 9]), 1);
    assert.equal(UC.compareSemver([0, 9, 9], [1, 0, 0]), -1);
});

test("compareSemver: minor dominates patch when major is equal", () => {
    assert.equal(UC.compareSemver([0, 5, 0], [0, 4, 99]), 1);
});

test("compareSemver: patch comparison kicks in last", () => {
    assert.equal(UC.compareSemver([0, 4, 1], [0, 4, 0]), 1);
});

test("compareSemver: null inputs are treated as equal-to-anything (safe default)", () => {
    assert.equal(UC.compareSemver(null, [0, 4, 0]), 0);
    assert.equal(UC.compareSemver([0, 4, 0], null), 0);
});

// ── isNewerVersion ─────────────────────────────────────────────────────

test("isNewerVersion: remote strictly newer → true", () => {
    assert.equal(UC.isNewerVersion("v0.4.0", "v0.5.0"), true);
    assert.equal(UC.isNewerVersion("0.4.0", "1.0.0"), true);
});

test("isNewerVersion: same / older / equal → false", () => {
    assert.equal(UC.isNewerVersion("v0.4.0", "v0.4.0"), false);
    assert.equal(UC.isNewerVersion("v0.5.0", "v0.4.0"), false);
});

test("isNewerVersion: malformed input → false (defensive)", () => {
    assert.equal(UC.isNewerVersion("v0.4.0", ""), false);
    assert.equal(UC.isNewerVersion("", "v0.5.0"), false);
    assert.equal(UC.isNewerVersion(null, "v0.5.0"), false);
});

// ── shouldRecheck ──────────────────────────────────────────────────────

test("shouldRecheck: never checked (lastCheckMs = 0) → recheck", () => {
    assert.equal(UC.shouldRecheck(0, Date.now(), 86_400_000), true);
});

test("shouldRecheck: TTL not yet elapsed → no recheck", () => {
    const now = 1_000_000_000;
    const fiveMinAgo = now - 5 * 60 * 1000;
    assert.equal(UC.shouldRecheck(fiveMinAgo, now, 86_400_000), false);
});

test("shouldRecheck: TTL elapsed → recheck", () => {
    const now = 1_000_000_000;
    const twoDaysAgo = now - 2 * 86_400_000;
    assert.equal(UC.shouldRecheck(twoDaysAgo, now, 86_400_000), true);
});

test("shouldRecheck: exactly at TTL → recheck (>=)", () => {
    const now = 1_000_000_000;
    assert.equal(UC.shouldRecheck(now - 86_400_000, now, 86_400_000), true);
});

test("shouldRecheck: non-finite lastCheck → recheck (treat as never)", () => {
    assert.equal(UC.shouldRecheck(NaN, Date.now(), 86_400_000), true);
});

// ── shouldNotify ───────────────────────────────────────────────────────

test("shouldNotify: same version → no notification", () => {
    assert.equal(UC.shouldNotify("v0.4.0", "v0.4.0", ""), false);
});

test("shouldNotify: newer remote, no acknowledgement → notify", () => {
    assert.equal(UC.shouldNotify("v0.4.0", "v0.5.0", ""), true);
});

test("shouldNotify: newer remote already acknowledged → no notification", () => {
    // User clicked "Got it" on v0.5.0; they don't need to see it again.
    assert.equal(UC.shouldNotify("v0.4.0", "v0.5.0", "v0.5.0"), false);
});

test("shouldNotify: newer remote AND newer than the acknowledged one → notify", () => {
    // User acknowledged v0.5.0 a while ago; v0.6.0 just landed → notify.
    assert.equal(UC.shouldNotify("v0.4.0", "v0.6.0", "v0.5.0"), true);
});

test("shouldNotify: acknowledged is OLDER than newly published — should still notify", () => {
    // User clicked "Got it" on v0.4.5, but the remote leapt to v0.5.0.
    assert.equal(UC.shouldNotify("v0.4.0", "v0.5.0", "v0.4.5"), true);
});

test("shouldNotify: malformed acknowledgement is treated as no-ack", () => {
    assert.equal(UC.shouldNotify("v0.4.0", "v0.5.0", "garbage"), true);
});
