#!/usr/bin/env bash
# Player-aware restart/update logic for the sdtd container. Two modes:
#
#   sdtd-restart.sh daily   (default) Restart if the server is EMPTY — the
#                           container's START_MODE=3 runs the SteamCMD update
#                           check on every start. Also restarts an unanswering
#                           (down/hung) server: that's recovery.
#   sdtd-restart.sh check   Hourly. If the server is EMPTY and Steam has a new
#                           stable build (LinuxGSM check-update), restart now so
#                           updates land within ~an hour of release instead of
#                           waiting for the daily window. Does nothing while
#                           anyone is online or while the server is booting.
#
# The player count comes from the public read-only Steam A2S query on the game
# port — no telnet/web-dashboard admin surface is needed (both stay disabled,
# see README). Skipped restarts simply retry at the next timer firing.
set -u
MODE="${1:-daily}"

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
  echo "sdtd-restart[$MODE]: $players player(s) online — not restarting"
  exit 0
fi

if [ "$MODE" = "check" ]; then
  if ! [ "$players" -eq 0 ] 2>/dev/null; then
    echo "sdtd-restart[check]: server not answering (down or mid-boot) — leaving it to the daily restart/watcher"
    exit 0
  fi
  out=$(docker exec -u sdtdserver -w /home/sdtdserver sdtd ./sdtdserver check-update 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
  if echo "$out" | grep -qi "no update available"; then
    echo "sdtd-restart[check]: already on the latest build — nothing to do"
    exit 0
  elif echo "$out" | grep -qi "update available"; then
    echo "sdtd-restart[check]: new build available and server empty — restarting to install"
    exec /usr/bin/docker restart sdtd
  else
    echo "sdtd-restart[check]: could not parse check-update output — doing nothing"
    echo "$out" | tail -n 5
    exit 0
  fi
fi

echo "sdtd-restart[daily]: server empty (a2s=$players) — restarting (update check runs on start)"
exec /usr/bin/docker restart sdtd
