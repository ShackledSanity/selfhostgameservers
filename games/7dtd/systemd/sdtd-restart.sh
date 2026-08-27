#!/usr/bin/env bash
# Player-aware daily restart. The restart is what triggers the SteamCMD update
# check (START_MODE=3 in docker-compose.yml), but nobody gets kicked for it:
# if anyone is online, skip and let the timer try again tomorrow. The player
# count comes from the public read-only Steam A2S query on the game port — no
# telnet/web-dashboard admin surface is needed (both stay disabled, see README).
# No answer (-1) means the server is down or hung, so a restart is recovery,
# not disruption — proceed.
set -u

players=$(python3 - <<'PY'
import socket, sys
addr = ("127.0.0.1", 26900)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(4)
req = b'\xFF\xFF\xFF\xFFTSource Engine Query\x00'
try:
    s.sendto(req, addr); d = s.recv(65535)
    if d[4:5] == b'A':  # challenge
        s.sendto(req + d[5:9], addr); d = s.recv(65535)
    if d[4:5] != b'I':
        print(-1); sys.exit()
    buf = d[5:]; i = 1  # skip protocol byte
    for _ in range(4):  # name, map, folder, game
        i = buf.index(b'\x00', i) + 1
    print(buf[i + 2])   # +2 skips appid short
except OSError:
    print(-1)
PY
)

if [ "$players" -gt 0 ] 2>/dev/null; then
  echo "sdtd-restart: $players player(s) online — skipping restart, next attempt tomorrow"
  exit 0
fi
echo "sdtd-restart: server empty (a2s=$players) — restarting to run the update check"
exec /usr/bin/docker restart sdtd
