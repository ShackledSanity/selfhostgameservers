# Valheim

Custom world modifiers, random seed, no admin.

## Admin surface, and how it is locked

Valheim's cheat surface is small and it is entirely **the admin list**. A player
whose SteamID64 appears in `adminlist.txt` can open the F5 console, type
`devcommands`, and then spawn items, fly, become invulnerable, kill every enemy
on the map or rewrite the world modifiers live. Nobody else can. There is no
admin password, and Valheim ships no RCON.

| Channel | How it's locked | Where |
|---|---|---|
| Admin list (`devcommands`, all cheats) | `ADMINLIST_IDS` empty | [`game.env`](game.env) |
| Supervisor HTTP management interface | `SUPERVISOR_HTTP=false`, port not published | [`game.env`](game.env) |
| Status HTTP page | `STATUS_HTTP=false`, port not published | [`game.env`](game.env) |
| Mod loaders (can reintroduce cheats) | `VALHEIM_PLUS=false`, `BEPINEX=false` | [`game.env`](game.env) |

`ADMINLIST_IDS` is authoritative in this image: it **overwrites** the live
`adminlist.txt` every time the container starts. So a hand-edit on the host is
undone within one restart — and in the meantime the watcher is hashing that file
and will alert. The audit workflow blocks any commit that fills the variable in.

The watcher also greps the container logs for `devcommands`, for a runtime admin
grant, and for either mod loader starting.

### Private join password

The server is gated by a join password, kept **private** exactly like Palworld's
and 7DTD's. The public [`game.env`](game.env) leaves `SERVER_PASS` empty; the
real value goes in `games/valheim/game.local.env` (gitignored).

**Valheim uses its own password, not the one the other servers share**, and it
does not arrive the same way either: unlike 7DTD there is no fallback to
Palworld's file, because this image reads `SERVER_PASS` only from its own env
files. It has to be written into `games/valheim/game.local.env` explicitly, and
`preflight.sh` fails if it is missing. The password grants zero privileges; it is
not an admin credential.

Valheim rejects a password shorter than 5 characters, or one that appears inside
the server name or the world name — which is why this server's password is
chosen against `RageQuit-Valheim` and `Yggdrasil` specifically, and why it is not
interchangeable with the other games'. `preflight.sh` enforces both rules against
the real value before deploy, so neither has to be reasoned about from this file.

## The world and its seed

The server generates its own world, named `Yggdrasil`, with a **random seed**
on first boot. Charl's call on 2026-09-29.

The world name is bound by the same rule as the password: Valheim refuses to
start if the join password is a substring of the server name, the world name or
the seed name. `Yggdrasil` is chosen to stay clear of it. Renaming it — or the
server — can break startup, and the error only appears in the container log, so
`preflight.sh` checks both against the real password (from gitignored
`game.local.env`) before a deploy can happen.

Worth knowing why that was the sensible choice: **Valheim dedicated servers have
no `-seed` argument.** You give the server a world *name*, and a chosen seed
would mean generating the world in the Valheim client and copying the `.fwl` and
`.db` onto the VM by hand — a manual step outside config-as-code, repeated every
time the world is reset.

**That generated world is the only irreplaceable thing on this box, and it is
not in git.** It lives in `data/config/worlds_local/`, which is gitignored
runtime state like every other game's saves. Deleting it does not "re-roll the
seed" — it destroys the save and generates a different world in its place.
The container keeps rolling backups in `/config/backups` (see `BACKUPS_*` in
[`game.env`](game.env)); those are on the same disk, so copy them somewhere else
if the world starts to matter.

If a specific seed is ever wanted, the world has to be pre-generated in the
client and staged before first boot. A seed only reproduces the same map for the
world-generator version that made it, and Iron Gate has changed generation
across major updates before — so it would have to be generated on the same
version the server runs.

## Applied gameplay settings

Set as world modifiers on the server command line — see `SERVER_ARGS` in
[`game.env`](game.env).

| Requested | Applied |
|---|---|
| Death penalty casual, minimal skill loss | `-modifier deathpenalty casual` — keep equipped gear, drop the rest, 1% skill loss |
| Resources 1.5× | `-modifier resources more` — exactly 1.5× |
| Portals unrestricted, all items | `-modifier portals casual` — everything passes, ores included |
| Combat / enemy damage / health / spawn rate / bosses / starred enemies: normal | default |
| Raid frequency + difficulty: normal | default |
| Building cost + damage, crafting cost + speed, food, stamina, skill gain: normal | default |
| Map enabled, sharing normal | default |

`normal` values are deliberately **left off** the command line. They are the
defaults, and Valheim's server refuses to start on an unrecognised modifier
value — so spelling them out could only break it.

### Requested settings Valheim has no equivalent for

Valheim's world modifiers are exactly five values (combat, death penalty,
resources, raids, portals) and four on/off keys (no build cost, player events,
passive mobs, no map). These requested items are **not separate settings** in
Valheim:

- **Resource respawn rate** — not adjustable; `resources` changes drop *amounts*
- **Building damage**, **crafting cost**, **crafting speed**, **food duration**,
  **stamina usage**, **skill gain rate** — not adjustable without mods
- **Bosses**, **starred enemies**, **enemy spawn rate** — folded into `combat`
- **Map sharing** — on/off only (via the `nomap` key), no "normal" tier

All of them were requested as *normal* anyway, so the server behaves as asked.
Changing any of them would need a mod loader, which is locked off here on
purpose — a mod that can change crafting costs can also change anything else.

## Auto-update

`UPDATE_CRON` is left at the image default (every 15 minutes) with
`UPDATE_IF_IDLE=true`. Valheim **clients** update themselves through Steam, and
a client newer than the server cannot connect — so a server that does not update
locks everyone out within hours of a patch. Same reasoning as 7DTD.

`UPDATE_IF_IDLE` means it waits for an empty server rather than dropping people
mid-raid. The container **image** stays digest-pinned in
[`stack.env`](stack.env) regardless; this only updates the game files from
Steam's own depot.

## Ports

| Port | Purpose |
|---|---|
| 2456/udp | game |
| 2457/udp | Steam query |

Crossplay is off. Turning it on (`CROSSPLAY=true`) lets Xbox and Game Pass
players join and additionally needs 2458/udp published in
[`docker-compose.yml`](docker-compose.yml) and added to `ports` in
[`manifest.json`](manifest.json).

## Deploying

1. **Preflight** — `bash games/valheim/preflight.sh`. It checks the join
   password is set and valid (Valheim silently starts an OPEN server without
   one) and tells you whether this deploy will create a new world or keep the
   existing one.
2. `./scripts/deploy.sh valheim` — opens 2456-2457/udp and brings up the
   container.
3. First boot downloads ~2 GB from Steam, so give it a few minutes. Watch with
   `docker logs -f valheim`.
4. Once it is up and `/config` is populated:
   `python3 watcher/watcher.py --approve valheim`, then commit
   [`config/approved.sha256`](config/approved.sha256).
5. Port-forward **2456-2457/udp** on the router to the VM.

### After the first boot

Check the world was created and then get it off this disk:

```bash
ls -l games/valheim/data/config/worlds_local/    # Yggdrasil.fwl + Yggdrasil.db
```

The container's own backups live in `/config/backups` on the same volume, which
covers a corrupted save but not a dead disk. This world is the only state here
that cannot be rebuilt from the repo.
