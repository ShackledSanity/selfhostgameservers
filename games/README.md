# Games

Each subdirectory is one **self-contained game server module**. The shared tooling
(watcher, audit workflow, heartbeat check, deploy, firewall) discovers games
automatically — adding a game is "drop in a folder," not "edit the tooling."

Directories whose name starts with `_` (e.g. `_template`) are ignored by the
tooling.

## Anatomy of a game module

```
games/<name>/
├── manifest.json        # drives watcher + audit + firewall (see below)
├── docker-compose.yml   # the server container; only game ports published
├── game.env             # gameplay settings + the admin locks
├── stack.env            # compose vars; image pinned by @sha256 digest
├── config/approved.sha256   # approved hash of the live config
└── README.md            # this game's admin surface + how it's locked
```

## `manifest.json` fields

| Field | Meaning |
|---|---|
| `name` / `display_name` | short id / friendly name |
| `container` | the docker container name to inspect + read logs from |
| `compose_dir` | path from repo root to this module |
| `live_config` | path (relative to `compose_dir`) of the generated config the watcher hashes |
| `ports` | firewall ports `deploy.sh` opens (e.g. `"8211/udp"`) |
| `image_pin_env` | file the audit checks for a `@sha256` pinned image |
| `source_checks` | key=value assertions on committed config the audit enforces (the admin locks) |
| `runtime_forbidden` | regexes the watcher must NOT find in the live config (admin re-enabled) |
| `log_forbidden` | regexes the watcher alerts on if seen in container logs |

## Adding a game

1. `cp -r games/_template games/<name>` and fill in `manifest.json`,
   `docker-compose.yml`, `game.env`, `stack.env`.
2. Pin the image by digest in `stack.env`; set the admin locks in `game.env` and
   mirror them in `source_checks` + `runtime_forbidden`.
3. Open a PR — `audit-config` must pass (admin locked + image pinned).
4. On the host: `./scripts/deploy.sh <name>`, then
   `python3 watcher/watcher.py --approve <name>` and commit its `approved.sha256`.
5. Port-forward the game's ports on your router to the VM.
