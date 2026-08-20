# 7 Days to Die — admin lockdown

7DTD's cheat surface spans **two files**, both published here as config-as-code
and both enforced on every commit (`audit-config` → `committed_checks` in
[`manifest.json`](manifest.json)) and watched live on the host
(`runtime_forbidden`). The container/service is named **`sdtd`**.

| Channel | Locked how | Where |
|---|---|---|
| In-game admin/cheat console (`cm`, `dm`, `spawnentity`, teleport…) | no admins granted | [`serveradmin.xml`](serveradmin.xml) — empty `<users>` |
| Telnet (remote admin console) | `TelnetEnabled=false`, empty `TelnetPassword` | [`serverconfig.xml`](serverconfig.xml) |
| Web Dashboard / control panel | `WebDashboardEnabled=false` (+ `ControlPanelEnabled` forbidden) | [`serverconfig.xml`](serverconfig.xml) |
| Local server console | `TerminalWindowEnabled=false` | [`serverconfig.xml`](serverconfig.xml) |
| Creative / god menu | `BuildCreate=false` | [`serverconfig.xml`](serverconfig.xml) |
| Client-side cheats | `EACEnabled=true` (Easy Anti-Cheat) | [`serverconfig.xml`](serverconfig.xml) |

To run an in-game admin/cheat command a player must be listed in
`serveradmin.xml` with a `permission_level` (0 = super-admin). That list is kept
**empty**, so no one — including the host — can. Adding any admin entry, or
flipping Telnet/Web Dashboard/creative on, **fails the audit** and fires a live
Discord alert within a minute.

- **Ports:** `26900/tcp` + `26900-26902/udp` (game). Telnet (8081), Web Dashboard
  (8080) and the Allocs map GUI (8082) are **never published**.
- **Live config watched:** `serverconfig.xml` (mounted read-only as the server's
  `sdtdserver.xml`) **and** the live `serveradmin.xml` under the save-data mount.
- **Image:** `vinanrra/7dtd-server`, pinned by digest in [`stack.env`](stack.env).

## Applied gameplay settings

Warrior difficulty; XP 100%; loot 125%, respawn 5 days; air drops every 3 days
(marker on); 60-minute days; blood moon every 7 days (range 0, count 8); zombies
walk by day / run at night; feral sense at night; PvP off; block-damage-AI 100%;
death penalty = lose backpack; enemy spawning on. All map 1:1 to
[`serverconfig.xml`](serverconfig.xml) and change only via pull request.

### Requested settings that are NOT dedicated-server options ⚠️

These have **no `serverconfig.xml` property** on a vanilla dedicated server and are
therefore **not applied**:

- **Harvest Amount (125–150%)**
- **Zombie Health (125%)**
- **Zombie Damage (125%)**
- Player→Zombie damage as a % / Trader Restock as a % (100% / Normal are the
  vanilla defaults anyway)

Applying them requires a server-side **modlet** (XML/XPath patches). Mods are code
that could alter balance or re-open a cheat surface, so — to keep this server
provably fair — one is **not** added silently. If you want these, we can add a
reviewed, public modlet under this module as a separate, audited change.

See the repo root [`TRUST.md`](../../TRUST.md) for how players verify all this.

## Deploy notes

1. `./scripts/deploy.sh 7dtd` (opens the game ports, brings up `sdtd`).
2. Let it install + generate its save data on first boot. Confirm
   `data/savedata/.../serveradmin.xml` exists; if its path differs on your host,
   fix `live_config[1]` in [`manifest.json`](manifest.json). Copy the generated
   `serveradmin.xml` over the committed baseline and commit it.
3. `python3 watcher/watcher.py --approve 7dtd`, then commit
   [`config/approved.sha256`](config/approved.sha256).
4. If LinuxGSM rejects the read-only `serverconfig.xml` mount, drop `:ro` in
   [`docker-compose.yml`](docker-compose.yml) and point `live_config[0]` at
   `data/serverfiles/sdtdserver.xml`.
5. Port-forward `26900/tcp` + `26900-26902/udp` to the VM.
