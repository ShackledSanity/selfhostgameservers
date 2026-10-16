# Enshrouded

Vanilla settings, one user group for everyone, no admin.

## Admin surface, and how it is locked

Enshrouded has no console, no RCON and no admin list. Its whole admin surface is
its **user groups**: each group in `enshrouded_server.json` has a password and a
set of permissions, and a player gets the permissions of whichever group's
password they type when they join. The one admin power is **kick/ban**
(`canKickBan`).

A fresh Enshrouded 1.0 server generates four groups with random passwords:
Admin (everything), Friend, Guest and Visitor. That layout assumes one trusted
host holding the Admin password, which is exactly what this repo exists to rule
out. So:

| Channel | How it's locked | Where |
|---|---|---|
| Kick/ban | the only group has `canKickBan=false` | [`game.env`](game.env) |
| A second, better-privileged password | exactly one group; `SERVER_ROLE_1_*` and above fail the audit | [`game.env`](game.env), [`manifest.json`](manifest.json) |
| Container hooks (shell commands run inside the server container) | none set; the audit fails if one is | [`game.env`](game.env) |
| Role reset (`supervisorctl start enshrouded-reset-roles`) | the watcher alerts if it runs | [`manifest.json`](manifest.json) |

The watcher checks the **live** config every minute and alerts if any group can
kick or ban, if a second group appears, if a group's password is emptied (the
server would then be open to anyone), or if a ban shows up — nobody can ban, so
a ban could only have been written in by hand. It also alerts if a container
hook runs or the roles are reset.

### Private join password

The server is gated by a join password, kept **private** exactly like the other
games'. It is the one group's password: the public [`game.env`](game.env) leaves
`SERVER_ROLE_0_PASSWORD` empty, and the real value goes in
`games/enshrouded/game.local.env` (gitignored, mode 600). Charl's call on
2026-10-16: the same password as Valheim.

Without that file the image gives the group an empty password and the server
starts **open**, so `preflight.sh` refuses to go ahead without it. The password
grants ordinary player permissions and nothing more.

## Settings: vanilla

Charl's call on 2026-10-16: vanilla server settings. Nothing gameplay-related
is set, so the server runs its own defaults — `gameSettingsPreset: "Default"`,
16 slots, voice and text chat off. Keen describes Default as "the recommended
setting for first-time players".

The file the server actually runs with is published in full in
[`config/approved-config.json`](config/approved-config.json), password blanked.
Its long `gameSettings` block is the server writing out its defaults, not
settings in force: per Keen, the individual settings only apply when the preset
is `Custom`. (One oddity in Keen's own material: the 1.0 readme's sample file
lists `randomSpawnerAmount: "Normal"`, while the 1.0 server writes `"Automatic"`.
Under `Default` neither is used.)

**The one deliberate difference from vanilla is the group's permissions.** With
no Admin, the single group gets the Admin group's permissions *minus*
kick/ban — which is vanilla's Friend plus `canExtendBase`. Extend base is what
places and grows Flame Altars, a base's footprint; a server of vanilla Friends
with nobody holding Admin could never start a base at all.

| Permission | Here | Vanilla Admin | Vanilla Friend |
|---|---|---|---|
| `canKickBan` | **no** | yes | no |
| `canAccessInventories` (chests, stations) | yes | yes | yes |
| `canEditWorld` (terraform outside bases) | yes | yes | yes |
| `canEditBase` (build inside bases) | yes | yes | yes |
| `canExtendBase` (Flame Altars) | yes | yes | **no** |

Why the preset is not set as `SERVER_GS_PRESET=Default` in `game.env`, even
though that is the same value: with any `SERVER_GS_*` variable present, this
image rewrites the config through a temp file and leaves it readable by its
owner only, so the watcher would see the config vanish for ~15 seconds on every
start. `preflight.sh` refuses to deploy with one set. The preset is pinned
anyway: it is part of the approved config.

## How the live config is checked

`data/game/server/enshrouded_server.json` is written twice on every start:
first by the container (from the `SERVER_*` variables), then by the server
itself a few seconds later, in its own layout. The bytes change each time; the
settings do not. So for this game the watcher hashes the **content** — it parses
the JSON and re-serialises it with keys sorted (`"live_config_format": "json"`
in [`manifest.json`](manifest.json)).

The file also holds the join password. The hash is published, and a hash of an
otherwise-public file plus one short password can be brute-forced back to the
password, so the watcher blanks every non-empty password before hashing. An
empty one is left as it is, so opening the server to anyone still changes the
hash.

[`config/approved.sha256`](config/approved.sha256) explains how to reproduce the
approved hash from [`config/approved-config.json`](config/approved-config.json)
with one line of Python.

A game update that adds a setting to the file changes the hash and raises a
drift alert, like a hand edit would. Check the new setting, then re-approve.

## The world

Enshrouded has one fixed map, so there is no seed to choose. The server created
its world on first boot. Enshrouded 1.0 stores it as
`data/game/server/savegame/world*.ksd`, saves it every 5 minutes (per Keen), and
keeps its own rolling copies in `savegame/backup/`.

**That world is the only irreplaceable thing in this module, and it is not in
git.** It is gitignored runtime state like every other game's saves, and it is
covered by the Proxmox backup of VM 110, which is on the same host.

The image's own backup job (`BACKUP_CRON`) is **not** used: in release 1.7.2 it
only understands the Early Access save layout and skips 1.0 worlds while
reporting success. The fix was merged upstream on 2026-10-15 and is in the
development build this server runs (see "The image"), but it has not been
tested here, so the job stays off.

## Auto-update

`UPDATE_CRON=*/15 * * * *` with `UPDATE_CHECK_PLAYERS=true`. Enshrouded
**clients** update themselves through Steam, and a client newer than the server
cannot join — so a server that does not update locks everyone out within hours
of a patch. Same reasoning as 7DTD and Valheim.

Every 15 minutes the image asks for Steam's current build number and installs a
new one only when the server is empty. It counts players over the public query
port, the same read-only A2S query 7DTD uses. Two dependencies are worth
knowing:

- The build number comes from the community `api.steamcmd.net` service, not from
  Valve. While that is down, no update is attempted at all.
- If the player count cannot be read, the image counts the server as empty.

The container **image** stays digest-pinned in [`stack.env`](stack.env)
regardless; this only updates the game files from Steam's own depot.

## The image

`mornedhels/enshrouded-server`, pinned by digest. Keen Games publishes no
official server image, so this is a community one, like every other game here.
Its supervisor listens on a socket inside the container only — no management
port to leave unpublished.

**Keen supports the dedicated server on Windows only** ("Linux support is
planned for later"). Every Linux host, this one included, runs the Windows
server under Wine or Proton, and Keen does not support that.

It is the image's **Proton** build, tag `dev-proton` (GE-Proton 11-9): a
development build the maintainers published on 2026-10-15, the day Enshrouded
1.0 came out. No numbered release runs 1.0 under Proton yet. Under the Proton
build of 1.7.2 the 1.0 server dies at startup with `Failed to initialize
Steamworks system...Version Mismatch` / `No SteamUtils011`; the dev build
starts cleanly (tested on this VM on 2026-10-16). Move to the first numbered
release after 1.7.2 once it is out.

**Why Proton.** The server first ran on the image's Wine build (Wine 11.0). It
worked, but with two players exploring it averaged 35-39 ms per world update
(4-6 ms with nobody on) and logged `[server] Bad Performance` every 5 seconds,
which players see as "high server load". The VM was 77% idle at the time. The
time went on thread synchronisation: that Wine build routes all of it through a
single `wineserver` process, which sat at ~70% CPU while the server made
~100,000 context switches a second. Proton does the same synchronisation in the
kernel instead (`fsync: up and running.` in its log). Side by side on copies of
the same world, both idle:

| | Wine build | Proton build |
|---|---|---|
| average world update | 4.3 ms | 1.8 ms |
| `wineserver` CPU | 16% | 0% |
| server context switches | ~16,400/s | ~2,800/s |

Both builds write the same server config from the same settings, so switching
between them does not change the approved hash. If the Proton build ever stops
working, the fallbacks in order are: back to the Wine build (its digest is in
`stack.env`; it works, but lags with players on), a newer image release, and
finally a Windows VM.

Measured on the Wine build on 2026-10-16: it reached `Host_Online` ~28 s after
the container started, answered the Steam query, and saved the world on its
own. A graceful stop saved the world first and exited with code 0 in ~18 s,
well inside the 90 s it is given. At the very last step of shutting down —
closing Steamworks, after the world was already on disk — it wrote a crash dump
(~320 KB) to `data/game/server/crash_dumps/`, one per stop. That is not a lost
save, and the folder can be emptied at any time. Two harmless error lines
appeared at every start: a Windows version value Wine does not provide
(`DisplayVersion`), and a missing component in a `Benchmark` template that has
nothing to do with gameplay. The same stop-and-save check on the Proton build is
part of switching the live server to it.

It runs as uid/gid 4711, which is not an account on the VM, with every Linux
capability dropped except the five the image's own hardening guide lists, and
`no-new-privileges`.

## Ports

| Port | Purpose |
|---|---|
| 15637/udp | everything: play, Steam query, server browser |

Keen lists one port, `queryPort` 15637, plus Steam's own ports, which the
server only needs outbound. Since Content Update 2 there is no separate game
port; older guides that list 15636 are out of date. Keen does not name a
protocol, so it was checked on the running 1.0 server: 15637 is bound on UDP
only, and nothing listens on TCP 15637. Forward UDP only. Multiplayer is IPv4
only.

## Joining

Per Keen's FAQ, players find it in the game, not by typing an address:

1. **Join** in the main menu.
2. In the server filter on the right, switch on **Show dedicated servers**.
   They are hidden by default.
3. Find `RageQuit-Enshrouded`, star it so it stays at the top, and join with
   the password.

If it does not show in the list, add it in Steam instead: **View → Game
Servers → Favorites → +** with `102.33.61.244:15637`.

## Resources

Keen's figures: the server uses ~4.4 GB of RAM idle plus up to 100 MB per
player, and recommends an 8-core/16-thread CPU and 16 GB of RAM for 16 players,
and 2 Mbit/s of upload per player. VM 110 has 64 GB and 16 vCPUs, shared with
the other servers. On this VM, `docker stats` showed ~0.8 GB with the world
loaded and nobody online, on either build.

## Deploying

1. **Preflight** — `bash games/enshrouded/preflight.sh`. It checks the join
   password is set, that nothing will make the live config unreadable to the
   watcher, and whether this deploy keeps an existing world.
2. `./scripts/deploy.sh enshrouded` — opens 15637/udp and brings up the
   container.
3. A first boot downloads ~8 GB from Steam. Watch with
   `docker logs -f enshrouded`; it is ready at `[Session] ... 'Host_Online'`.
4. If a setting changed: `python3 watcher/watcher.py --approve enshrouded`, then
   commit **both** `config/approved.sha256` and `config/approved-config.json`.
5. Port-forward **15637/udp** on the router to the VM.

## Honest limits

- **Characters live on each player's own PC.** In Keen's words, "Character
  progression is stored only on clients" — the server holds the world, not the
  characters. Anyone can bring a character in from another world, so this
  server can vouch for the world's rules but not for what a character arrives
  with.
- **Nobody can kick or ban, including Charl.** With one shared password and
  every player able to open chests and edit bases, a griefer who has the
  password can only be stopped by changing it in `game.local.env` and
  restarting — which locks everyone out until they have the new one.

## Keen's own documentation

Checked against on 2026-10-16:

- `enshrouded_server_readme.txt`, shipped with the server build itself
  ("Version: 1.0.0.0") — every setting, the four default groups, what each
  permission does, and the default 1.0 config. It is in
  `data/game/server/` on the VM.
- Keen's help centre: [Dedicated Server Installation](https://enshrouded.zendesk.com/hc/en-us/articles/16051370691485-Dedicated-Server-Installation-on-Steam),
  [Dedicated Server FAQ](https://enshrouded.zendesk.com/hc/en-us/articles/16056312924957-Dedicated-Server-FAQ),
  [Dedicated Server Configuration](https://enshrouded.zendesk.com/hc/en-us/articles/16055441447709-Dedicated-Server-Configuration),
  [Server Roles Configuration](https://enshrouded.zendesk.com/hc/en-us/articles/19191581489309-Server-Roles-Configuration),
  [Server Gameplay Settings](https://enshrouded.zendesk.com/hc/en-us/articles/20453241249821-Server-Gameplay-Settings),
  [Recommended Server Specifications](https://enshrouded.zendesk.com/hc/en-us/articles/16055628734109-Recommended-Server-Specifications).
  None of them had been edited for 1.0 yet, so where they differ from the
  readme, the readme wins: for example, the 1.0 server writes its ban list as
  `bannedAccounts`, where older documents say `bans`. The watcher checks both
  names.
