#!/usr/bin/env bash
# GitOps deploy: pull the signed public config and bring game servers up.
# Run on the VM. It never hand-edits config — the git repo is the source of truth.
#
#   ./scripts/deploy.sh            # deploy every game under games/
#   ./scripts/deploy.sh palworld   # deploy just one game
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Fetching latest signed config"
git fetch origin
git checkout main
git pull --ff-only
if git verify-commit HEAD >/dev/null 2>&1; then
  echo "==> HEAD commit signature: OK"
else
  if [ "${REQUIRE_SIGNED:-0}" = "1" ]; then
    echo "ERROR: HEAD is not a verified signed commit; refusing to deploy (REQUIRE_SIGNED=1)." >&2
    exit 1
  fi
  echo "WARNING: HEAD is not a verified signed commit (set REQUIRE_SIGNED=1 to enforce once signing is configured)." >&2
fi

deploy_game() {
  local dir="$1"
  local name; name="$(basename "$dir")"
  [ -f "$dir/docker-compose.yml" ] || { echo "skip $name (no compose)"; return 0; }

  # A retired game stays down, even when asked for by name: bringing it back is a
  # public commit that removes "retired" from its manifest, not a deploy flag.
  local retired
  retired="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("retired") or "")' "$dir/manifest.json" 2>/dev/null || true)"
  if [ -n "$retired" ]; then
    echo "skip $name (retired $retired; to bring it back, remove \"retired\" from its manifest.json)"
    return 0
  fi

  echo "==> Deploying $name"

  # Open the firewall ports this game declares in its manifest.
  if [ -f "$dir/manifest.json" ] && command -v ufw >/dev/null 2>&1; then
    for p in $(python3 -c "import json;print(' '.join(json.load(open('$dir/manifest.json')).get('ports',[])))"); do
      sudo ufw allow "$p" >/dev/null || true
    done
  fi

  ( cd "$dir" && docker compose --env-file stack.env up -d )
}

if [ "${1:-}" != "" ]; then
  deploy_game "games/$1"
else
  for d in games/*/; do
    case "$(basename "$d")" in _*) continue ;; esac
    deploy_game "$d"
  done
fi

echo
echo "If you changed a setting, refresh that game's approved hash:"
echo "  python3 watcher/watcher.py --approve <game>   # then commit games/<game>/config/approved.sha256"
