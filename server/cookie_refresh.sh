#!/bin/bash
# Re-export the logged-in YouTube cookies from the VPS Chrome profile into
# ~/aurora/cookies.txt. Chrome encrypts cookies (v11) with a key in the GNOME
# keyring, so we must borrow the live xfce session's DBUS address to unlock it.
# Keep Chrome signed in to keep these fresh. Runs on a timer (see
# cookie-refresh.timer). Needs secretstorage+jeepney in the venv.
set -u
cd ~/aurora || exit 1
export PATH=/usr/local/bin:$PATH

PID=$(pgrep -x xfce4-session | head -1)
[ -z "$PID" ] && { echo "cookie-refresh: no xfce session (RDP not started?)"; exit 1; }
export DBUS_SESSION_BUS_ADDRESS=$(tr '\0' '\n' < "/proc/$PID/environ" \
  | grep -m1 '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)

./venv/bin/python - <<'PY'
import os
from yt_dlp.cookies import extract_cookies_from_browser, YDLLogger
try:
    jar = extract_cookies_from_browser("chrome", logger=YDLLogger(),
                                       keyring="GNOMEKEYRING")
    tmp = "/tmp/ck_new.txt"
    jar.save(tmp, ignore_discard=True, ignore_expires=True)
    n = sum(1 for l in open(tmp)
            if "google" in l.lower() or "youtube" in l.lower())
    if n >= 10:
        os.replace(tmp, os.path.expanduser("~/aurora/cookies.txt"))
        print(f"cookie-refresh: OK ({n} google/youtube lines)")
    else:
        print(f"cookie-refresh: only {n} cookies — keeping previous")
except Exception as e:
    print("cookie-refresh: FAILED", e)
PY
