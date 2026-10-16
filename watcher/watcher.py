#!/usr/bin/env python3
"""
Provably-fair game-server watcher (multi-game).

Runs on the game host. Discovers every game under games/<name>/manifest.json
(folders starting with '_' are ignored) and, each cycle, for each game:
  - hashes the live config and compares it to the game's approved hash,
  - verifies the admin locks are OFF (manifest 'runtime_forbidden' rules),
  - scans the container logs for forbidden admin activity ('log_forbidden'),
  - writes heartbeat/<name>.json and (periodically) pushes them to GitHub so the
    off-host GitHub Action can confirm each server is alive and unmodified.

Any drift or admin activity is posted to Discord immediately.

Usage:
  python3 watcher.py                 # watch loop over ALL games
  python3 watcher.py --approve       # record approved hash for ALL games, then exit
  python3 watcher.py --approve NAME  # record approved hash for one game, then exit
"""
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def load_env(path):
    env = {}
    p = Path(path)
    if p.exists():
        for line in p.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


CFG = {**load_env(Path(__file__).with_name("watcher.env")), **os.environ}
REPO_DIR = CFG.get("REPO_DIR", str(Path(__file__).resolve().parents[1]))
WEBHOOK = CFG.get("DISCORD_WEBHOOK_URL", "")
CHECK_INTERVAL = int(CFG.get("CHECK_INTERVAL", "60"))
PUSH_INTERVAL = int(CFG.get("PUSH_INTERVAL", "300"))
HEARTBEAT_PUSH = CFG.get("HEARTBEAT_PUSH", "false").lower() == "true"
GIT_REMOTE = CFG.get("GIT_REMOTE", "origin")
# Heartbeats push to their own branch/checkout so `main` can be branch-protected.
HEARTBEAT_REPO = CFG.get("HEARTBEAT_REPO", REPO_DIR)
HEARTBEAT_BRANCH = CFG.get("HEARTBEAT_BRANCH", "main")


def sh(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception as e:
        print(f"cmd failed {args}: {e}")
        return ""


def discover_games():
    games = []
    for mpath in sorted(glob.glob(os.path.join(REPO_DIR, "games", "*", "manifest.json"))):
        if os.path.basename(os.path.dirname(mpath)).startswith("_"):
            continue
        try:
            games.append(json.loads(Path(mpath).read_text()))
        except Exception as e:
            print(f"bad manifest {mpath}: {e}")
    return games


def live_config_paths(m):
    """Absolute path(s) of the game's live config. `live_config` may be a single
    string (one file) or a list of strings (several files, e.g. a game whose admin
    surface spans multiple config files)."""
    lc = m["live_config"]
    rels = lc if isinstance(lc, list) else [lc]
    return [os.path.join(REPO_DIR, m["compose_dir"], r) for r in rels]


def read_live_config(m):
    """Read the game's live config as one text blob.

    Single file -> exactly that file's text (so a one-file game's hash, drift
    check and heartbeat are byte-identical to before this multi-file support).
    Multiple files -> concatenated in manifest order with a per-file delimiter;
    None if ANY listed file is missing (server likely down / not generated yet)."""
    paths = live_config_paths(m)
    if len(paths) == 1:
        return read_text(paths[0])
    parts = []
    for p in paths:
        t = read_text(p)
        if t is None:
            return None
        parts.append(f"# <<< {os.path.basename(p)} >>>\n{t}")
    return "\n".join(parts)


def approved_path(m):
    return os.path.join(REPO_DIR, m["compose_dir"], "config", "approved.sha256")


def read_text(p):
    try:
        return Path(p).read_text(errors="replace")
    except OSError:
        # Missing (server not up yet) OR unreadable (e.g. a container left it
        # owner-only). Either way the watcher cannot vouch for it, so it reports
        # config-missing - instead of a PermissionError killing the loop, which
        # would silence the checks for every game until it was fixed.
        return None


REDACTED = "<redacted>"


def _redact(o):
    if isinstance(o, dict):
        return {k: (REDACTED if k == "password" and isinstance(v, str) and v else _redact(v))
                for k, v in o.items()}
    if isinstance(o, list):
        return [_redact(v) for v in o]
    return o


def normalise(m, text):
    """The text that is hashed and checked. Identical to the file for every game
    except one whose manifest sets "live_config_format": "json".

    For those, the CONTENT is hashed, not the layout: the JSON is parsed and
    re-serialised with sorted keys and fixed separators. Enshrouded needs this - its
    container writes the config (2-space jq layout) and the server rewrites it in
    its own tab layout ~30 seconds later, so the raw bytes change on every start
    while the settings stay the same.

    The file also holds the join password. The hash is published (approved.sha256,
    heartbeats), and a hash over an otherwise-public file plus one short password
    can be brute-forced back to the password, so every non-empty "password" value is
    replaced with a fixed marker first. An EMPTY one is left as it is: a server
    opened to anyone still changes the hash."""
    if text is None or m.get("live_config_format") != "json":
        return text
    try:
        data = json.loads(text)
    except ValueError:
        return text  # caught mid-write, or corrupt: hashes as drift if it persists
    return json.dumps(_redact(data), sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256(text):
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest() if text is not None else None


def read_approved(m):
    try:
        for line in Path(approved_path(m)).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                return line
    except FileNotFoundError:
        pass
    return None


def runtime_violations(m, text):
    return [r["message"] for r in m.get("runtime_forbidden", []) if re.search(r["pattern"], text, re.I)]


def log_violations(m):
    logs = sh(["docker", "logs", "--since", "120s", m["container"]])
    return [r["message"] for r in m.get("log_forbidden", []) if re.search(r["pattern"], logs, re.I)]


def image_digest(container):
    return sh(["docker", "inspect", "--format", "{{.Image}}", container]) or "unknown"


def container_status(container):
    """Return (running: bool, health: str, started_iso: str) for the game container."""
    out = sh(["docker", "inspect", "--format",
              "{{.State.Running}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}|{{.State.StartedAt}}",
              container])
    parts = out.split("|") if out else []
    running = len(parts) > 0 and parts[0].strip() == "true"
    health = parts[1].strip() if len(parts) > 1 else "unknown"
    started = parts[2].strip() if len(parts) > 2 else ""
    return running, health, started


def git_commit():
    return sh(["git", "-C", REPO_DIR, "rev-parse", "--short", "HEAD"]) or "unknown"


def discord(title, lines):
    if not WEBHOOK:
        print(f"[no webhook] {title}: {lines}")
        return
    desc = "\n".join(f"• {l}" for l in lines) if isinstance(lines, list) else str(lines)
    payload = {"embeds": [{"title": title, "description": desc, "color": 0xE01E1E}]}
    try:
        req = urllib.request.Request(
            WEBHOOK, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json", "User-Agent": "RageQuit-Iris/1.0"}
        )
        urllib.request.urlopen(req, timeout=15)
    except Exception as e:
        print(f"discord post failed: {e}")


def heartbeat_path(name):
    return os.path.join(HEARTBEAT_REPO, "heartbeat", f"{name}.json")


def write_heartbeat(m, status, live_hash, approved, srv):
    hp = heartbeat_path(m["name"])
    os.makedirs(os.path.dirname(hp), exist_ok=True)
    running, health, started = srv
    hb = {
        "game": m["name"],
        "ts": int(time.time()),
        "iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "status": status,
        "server_running": running,
        "server_health": health,
        "server_started": started,
        "runtime_config_sha256": live_hash,
        "approved_config_sha256": approved,
        "image": image_digest(m["container"]),
        "git_commit": git_commit(),
    }
    Path(hp).write_text(json.dumps(hb, indent=2) + "\n")


def push_heartbeats():
    sh(["git", "-C", HEARTBEAT_REPO, "add", "heartbeat"])
    sh(["git", "-C", HEARTBEAT_REPO, "commit", "-m", "heartbeat", "--no-verify"])
    sh(["git", "-C", HEARTBEAT_REPO, "push", GIT_REMOTE, HEARTBEAT_BRANCH])


def approve(one=None):
    found = False
    for m in discover_games():
        if one and m["name"] != one:
            continue
        found = True
        text = normalise(m, read_live_config(m))
        if text is None:
            print(f"[{m['name']}] live config not found at {', '.join(live_config_paths(m))} — start it first.")
            continue
        public = None
        if m.get("live_config_format") == "json":
            try:
                public = json.dumps(json.loads(text), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
            except ValueError:
                print(f"[{m['name']}] live config is not valid JSON right now (mid-write?) — not approving; retry.")
                continue
        h = sha256(text)
        ap = approved_path(m)
        os.makedirs(os.path.dirname(ap), exist_ok=True)
        Path(ap).write_text(h + "\n")
        print(f"[{m['name']}] approved {h}\n  wrote {ap} — commit it.")
        if public is not None:
            # The approved settings in full, password blanked, for anyone to read.
            # approved.sha256 is the sha256 of exactly this content in compact form
            # (sorted keys, "," and ":" separators), so it can be checked by hand.
            pp = os.path.join(os.path.dirname(ap), "approved-config.json")
            Path(pp).write_text(public)
            print(f"  wrote {pp} — commit it too.")
    if one and not found:
        print(f"No game named '{one}' found under games/.")


def main():
    if "--approve" in sys.argv:
        i = sys.argv.index("--approve")
        approve(sys.argv[i + 1] if len(sys.argv) > i + 1 else None)
        return

    print("watcher: starting (multi-game)")
    last_alert = {}  # name -> last-alerted config hash (dedupe)
    last_push = 0.0
    while True:
        for m in discover_games():
            text = normalise(m, read_live_config(m))
            live_hash = sha256(text)
            approved = read_approved(m)
            problems = []
            status = "ok"

            srv = container_status(m["container"])
            if text is None:
                problems.append("live config not found — server may be down")
                status = "config-missing"
            else:
                problems += runtime_violations(m, text)
                problems += log_violations(m)
                if approved and approved != "REPLACE_AFTER_FIRST_DEPLOY" and live_hash != approved:
                    problems.append(f"config DRIFT: live {live_hash[:12]} != approved {approved[:12]}")
                if problems:
                    status = "violation"
            if not srv[0]:  # container not running
                problems.append("server is OFFLINE (container not running)")
                if status == "ok":
                    status = "server-down"

            if problems and last_alert.get(m["name"]) != (live_hash, srv[0]):
                discord(f"⚠️ {m.get('display_name', m['name'])} integrity alert", problems)
                last_alert[m["name"]] = (live_hash, srv[0])

            write_heartbeat(m, status, live_hash, approved, srv)

        now = time.time()
        if HEARTBEAT_PUSH and now - last_push >= PUSH_INTERVAL:
            push_heartbeats()
            last_push = now

        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
