#!/bin/bash
# Push the current Cloudflare quick-tunnel URL to Vercel Edge Config so the
# registry serves it without a redeploy. Runs after cloudflared (re)starts.
# Secrets live in ~/aurora/vercel.env (gitignored, never committed):
#   VERCEL_TOKEN=...
#   EDGE_CONFIG_ID=ecfg_...
#   VERCEL_TEAM_ID=team_...
set -u
cd ~/aurora || exit 1
[ -f vercel.env ] && set -a && . ./vercel.env && set +a

LOG=~/cloudflared.log
LAST=~/aurora/.last_url
LASTV=""; [ -f "$LAST" ] && LASTV=$(cat "$LAST")

# Poll the cloudflared log up to 90s for a trycloudflare URL that differs from
# the last one we pushed. cloudflared appends to its logfile, so right after a
# restart the old URL is still the newest line until the new one is written —
# waiting for a *different* URL avoids re-pushing the stale one.
URL=""
for i in $(seq 1 90); do
  C=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | tail -1)
  if [ -n "$C" ] && [ "$C" != "$LASTV" ]; then URL="$C"; break; fi
  sleep 1
done
[ -z "$URL" ] && { echo "register: no new tunnel URL after 90s (last=$LASTV)"; exit 0; }

CODE=$(curl -s -o /tmp/vc_resp.json -w '%{http_code}' -m 25 -X PATCH \
  "https://api.vercel.com/v1/edge-config/${EDGE_CONFIG_ID}/items?teamId=${VERCEL_TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"items\":[{\"operation\":\"upsert\",\"key\":\"backend_url\",\"value\":\"${URL}\"}]}")

if [ "$CODE" = "200" ]; then
  echo "$URL" > "$LAST"
  echo "register: pushed $URL"
else
  echo "register: FAILED http=$CODE $(cat /tmp/vc_resp.json)"
  exit 1
fi
