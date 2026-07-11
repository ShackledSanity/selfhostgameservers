# Security posture & GitHub hardening checklist

This repo is **public by design** — config-as-code is what lets players verify the
servers are fair. **No secrets live here:** the Discord webhook and the watcher's
git-push credential exist only on the host in git-ignored files (`watcher/watcher.env`),
and admin is disabled at the config level (see each `games/<name>/README.md`).

## What must be ENABLED on GitHub (repo → Settings)

- [ ] **Branch protection on `main`** (Settings → Branches → Add branch ruleset):
  - Require a pull request before merging
  - Require signed commits
  - Block force pushes; block deletions
  - Include administrators / "Do not allow bypassing" — so even the owner can't
    quietly land a change (this is core to the fairness guarantee)
- [ ] **Secret scanning + Push protection** (Settings → Code security): blocks any
  accidental secret from ever being committed.
- [ ] **Actions permissions** (Settings → Actions → General):
  - Workflow permissions = **Read repository contents** (least privilege — the
    workflows never write)
  - Fork PRs from outside collaborators: **require approval**
  - **Uncheck** "Allow GitHub Actions to create and approve pull requests"
- [ ] **Actions secret** `DISCORD_WEBHOOK_URL` (Settings → Secrets and variables →
  Actions) — the only secret; nothing else belongs here.
- [ ] **Deploy key** (Settings → Deploy keys): a single key with **write access**
  for the watcher's heartbeat pushes. Use this, not an account-wide PAT.

## Why `main` is protected yet the watcher still works

The watcher pushes machine heartbeats to a dedicated **`heartbeat` branch**, never
to `main`. So `main` can require PRs and signed commits (locking config down)
while the watcher pushes freely to its own branch. That branch's commit history is
the append-only audit trail the off-host workflow reads.

## The honest limit

The host has root on the box and owns this GitHub account, so this is
**tamper-evidence, not impossibility** (see [TRUST.md](TRUST.md)). For the maximum
guarantee, a neutral player holds the `DISCORD_WEBHOOK_URL` secret and owns branch
protection.

## Reporting

Found a way to bypass the fairness guarantees? Open an issue or ping the Discord.
