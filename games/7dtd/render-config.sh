#!/usr/bin/env bash
# Render the LIVE 7DTD config (data/serverfiles/sdtdserver.xml) from the PUBLIC,
# admin-locked serverconfig.xml, injecting the PRIVATE join password so it never
# enters the public repo. Idempotent — run before ./scripts/deploy.sh 7dtd and
# after any serverconfig.xml change.
#
# The join password is taken, in order, from:
#   1. games/7dtd/game.local.env      (SERVER_PASSWORD=...)   [gitignored]
#   2. games/palworld/game.local.env  (SERVER_PASSWORD=...)   [gitignored]  <- "same as Palworld"
#   3. empty (open server)
#
# Only the ServerPassword value is changed; the admin locks are never touched.
set -euo pipefail
cd "$(dirname "$0")"

read_pw() { [ -f "$1" ] && grep -E '^SERVER_PASSWORD=' "$1" | head -n1 | cut -d= -f2- | tr -d '\r'; }

PW="$(read_pw game.local.env || true)"
[ -n "$PW" ] || PW="$(read_pw ../palworld/game.local.env || true)"

DST="data/serverfiles/sdtdserver.xml"
mkdir -p "$(dirname "$DST")"

SERVER_PASSWORD="$PW" python3 - "serverconfig.xml" "$DST" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
pw = os.environ.get("SERVER_PASSWORD", "")
if '"' in pw:
    sys.exit('ERROR: the join password must not contain a double-quote (").')
text = open(src, encoding="utf-8").read()
text, n = re.subn(r'(name="ServerPassword"\s+value=")[^"]*(")',
                  lambda m: m.group(1) + pw + m.group(2), text, count=1)
if n != 1:
    sys.exit("ERROR: ServerPassword property not found in " + src)
with open(dst, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)
print(f"rendered {dst} (ServerPassword {'set (private)' if pw else 'empty / open server'})")
PY
