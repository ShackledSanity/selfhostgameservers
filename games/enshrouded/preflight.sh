#!/usr/bin/env bash
# Pre-deploy checks for Enshrouded.
#
# Guards the two things that fail quietly:
#   - the join password. Without it the image gives the one user group an EMPTY
#     password and the server starts OPEN to anyone who finds it.
#   - the live config staying readable by the watcher. This image rewrites the
#     config owner-only whenever a SERVER_GS_* variable is set, and the watcher
#     (its own user) then cannot read it at all.
#
# It also says, once, whether this deploy keeps an existing world or starts one.
#
# Run from anywhere:  bash games/enshrouded/preflight.sh
set -euo pipefail
cd "$(dirname "$0")"

DATA_DIR="$(grep -E '^DATA_DIR=' stack.env | head -1 | cut -d= -f2-)"
SERVER_DIR="${DATA_DIR%/}/game/server"
CONFIG="${SERVER_DIR}/enshrouded_server.json"

echo "==> Enshrouded preflight"
fail=0

# ── join password ────────────────────────────────────────────────────────────
# Nothing below ever prints the password itself.
if [ -f game.local.env ] && grep -qE '^SERVER_ROLE_0_PASSWORD=.+' game.local.env; then
  pass="$(grep -E '^SERVER_ROLE_0_PASSWORD=' game.local.env | head -1 | cut -d= -f2-)"
  echo "    password   : set in game.local.env (${#pass} characters)"
  if [ "$(stat -c %a game.local.env)" != "600" ]; then
    echo "    WARNING    : game.local.env is mode $(stat -c %a game.local.env) - expected 600 (root only)" >&2
  fi
else
  cat >&2 <<'EOS'
    ERROR      : no join password.

                 Create games/enshrouded/game.local.env (gitignored, chmod 600) with:
                     SERVER_ROLE_0_PASSWORD=your-password-here

                 Without it the one user group gets an EMPTY password and the
                 server starts OPEN to anyone.
EOS
  fail=1
fi

# ── settings that would blind the watcher ───────────────────────────────────
if grep -qE '^\s*SERVER_GS_' game.env game.local.env 2>/dev/null; then
  echo "    ERROR      : a SERVER_GS_* variable is set:" >&2
  grep -nE '^\s*SERVER_GS_' game.env game.local.env 2>/dev/null | sed 's/=.*/=.../; s/^/                   /' >&2
  echo "                 With any of these, this image rewrites the live config" >&2
  echo "                 owner-only and the watcher can no longer read it. See" >&2
  echo "                 the note under 'Gameplay: vanilla' in game.env." >&2
  fail=1
fi
if [ -f "$CONFIG" ]; then
  mode="$(stat -c %a "$CONFIG")"
  if [ "$(( 0${mode: -1} & 4 ))" -eq 0 ]; then
    echo "    ERROR      : the live config is mode ${mode} - the watcher cannot read it." >&2
    echo "                 Fix once with:  chmod 644 ${CONFIG}" >&2
    fail=1
  else
    echo "    live config: present, mode ${mode} (readable by the watcher)"
  fi
fi

# ── world state ──────────────────────────────────────────────────────────────
# Enshrouded 1.0 keeps the world as savegame/world*.ksd, with its own rolling
# copies in savegame/backup. Early Access used a 3ad85aea-index layout instead;
# check both so a live world is never reported as "none yet".
if ls "${SERVER_DIR}/savegame"/world*.ksd >/dev/null 2>&1 \
   || [ -f "${SERVER_DIR}/savegame/3ad85aea-index" ]; then
  echo "    world      : exists already - this deploy will KEEP it"
  printf '                 %s  (%s)\n' "${SERVER_DIR}/savegame" \
    "$(du -sh "${SERVER_DIR}/savegame" 2>/dev/null | cut -f1)"
else
  echo "    world      : none yet - the server will CREATE one on first boot."
  echo "                 That world becomes the only irreplaceable state here and"
  echo "                 it is NOT in git."
fi

if [ "$fail" -ne 0 ]; then
  echo >&2
  echo "NOT READY TO DEPLOY - fix the errors above and re-run." >&2
  exit 1
fi

echo "==> OK - safe to run ./scripts/deploy.sh enshrouded"
