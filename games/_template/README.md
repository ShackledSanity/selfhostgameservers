# _template — copy me to add a game

```bash
cp -r games/_template games/<name>
```

Then fill in, in the new folder:
1. **`manifest.json`** — `name`, `display_name`, `container`, `compose_dir`
   (`games/<name>`), `live_config`, `ports`, and the admin-lock rules
   (`source_checks` + `runtime_forbidden`).
2. **`docker-compose.yml`** — the server image + volume; publish only game ports.
3. **`game.env`** — gameplay settings and the admin locks (keep admin disabled).
4. **`stack.env`** — pin the image by `@sha256` digest; set `SAVE_DIR`, `GAME_PORT`.

Then: open a PR (must pass `audit-config`), `./scripts/deploy.sh <name>`,
`python3 watcher/watcher.py --approve <name>`, commit `config/approved.sha256`.

See [`../README.md`](../README.md) for the full field reference. Folders starting
with `_` are ignored by the tooling.
