# How you can trust these servers are fair

These game servers are run by someone who **also plays on them**. To make sure
that person (or anyone else) can't cheat using admin commands, everything about
every server is public and continuously audited. Here's how you can check it
yourself.

## The promise

- **There is no live admin.** Each game's admin powers are turned **off** at the
  config level (for Palworld: no admin password, no RCON, no REST API — see
  [`games/palworld/README.md`](games/palworld/README.md)).
- **Every setting is public.** The full config for each game lives in this repo
  under [`games/`](games/). Nobody can change a setting without it becoming a
  public, timestamped commit.
- **Any tampering is announced.** A watcher checks every live server each minute
  and posts to our Discord the instant anything drifts or any admin channel turns on.

## Verify it yourself (takes 2 minutes)

1. **Open the game's `game.env`** (e.g. [`games/palworld/game.env`](games/palworld/game.env))
   and confirm the admin locks are set — for Palworld:
   `ADMIN_PASSWORD=` (empty), `RCON_ENABLED=false`, `REST_API_ENABLED=false`.
2. **Check the audit badge.** The `audit-config` GitHub Action runs on every change
   and **fails** if any game re-enables admin or unpins its image. Green = every
   published config is admin-free.
3. **Check the heartbeats.** The `heartbeat-check` Action runs every ~15 minutes on
   GitHub's own servers (not the host's) and confirms each live server still matches
   its approved config. Look at [`heartbeat/`](heartbeat/) — one file per game — and
   its commit history; those timestamps are stamped by GitHub, not the host.
4. **Watch the Discord channel.** Config changes and any admin activity land there
   in real time.

## What an alert looks like

If someone edits a config on the box, turns on RCON/REST, sets an admin password,
or a server goes silent, you'll see a red **integrity alert** (from the host) or
**off-host audit** (from GitHub) in Discord within a minute or two — naming the
game and the problem.

## The honest limits (why we're telling you this)

The host owns the physical machine, so at the hardware level they have root. This
system is built for **tamper-evidence, not impossibility** — to cheat, the host
would have to either (a) change a config, which changes its hash and fires an
alert, (b) actively and continuously forge the public heartbeat while hiding the
real state, or (c) take a server offline (a stale heartbeat). None are silent.

The one remaining gap: the host currently also controls the GitHub repo's alert
settings. To close it completely — and make this as strong as a neutral
third-party host — a **player who isn't the host** can hold the Discord webhook
secret and own the repo's branch protection. Ask about that if you want the
maximum guarantee. Nothing here is hidden; that's the whole point.
