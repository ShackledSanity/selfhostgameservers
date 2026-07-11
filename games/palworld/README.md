# Palworld — admin lockdown

Palworld's entire admin surface is **three switches, all keyed off one password**.
With all three off, there is no way for anyone (including the host) to run an
admin/cheat command — Palworld has no per-player admin roles.

| Channel | `game.env` key | Locked how |
|---|---|---|
| In-game `/admin` commands | `ADMIN_PASSWORD` | left empty |
| RCON (remote console) | `RCON_ENABLED` | `false` |
| REST API | `REST_API_ENABLED` | `false` |

These three are enforced on every commit by the `audit-config` workflow
(`source_checks` in [`manifest.json`](manifest.json)) and watched live by the
watcher (`runtime_forbidden`). All other gameplay settings in `game.env` map 1:1
to `PalWorldSettings.ini` and are changed only via pull request.

- **Ports:** `8211/udp` (game) + `27015/udp` (community browser). RCON (25575) and
  REST (8212) are never published.
- **Live config watched:** `saves/Config/LinuxServer/PalWorldSettings.ini`.
- **Image:** pinned by digest in [`stack.env`](stack.env).

See the repo root [`TRUST.md`](../../TRUST.md) for how players verify all this.
