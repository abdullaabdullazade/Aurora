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

# Poll the cloudflared log up to 60s for the trycloudflare URL.
URL=""
for i in $(seq 1 60); do
  URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | tail -1)
  [ -n "$URL" ] && break
  sleep 1
done
[ -z "$URL" ] && { echo "register: no tunnel URL after 60s"; exit 1; }

# Skip if unchanged.
[ -f "$LAST" ] && [ "$(cat "$LAST")" = "$URL" ] && { echo "register: unchanged ($URL)"; exit 0; }

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
