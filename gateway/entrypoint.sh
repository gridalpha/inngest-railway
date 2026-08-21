#!/bin/sh
# Boot wrapper for the Caddy auth gateway.
set -eu

# A ${{inngest.RAILWAY_PRIVATE_DOMAIN}} reference renders empty until that
# service owns a deployment, and Caddy would then bake "http://:8288" as its
# upstream and 502 until something restarted it. Private hostnames are
# deterministic, so default on the value's shape instead.
case "${INNGEST_UPSTREAM:-}" in
	"" | :*) INNGEST_UPSTREAM="inngest.railway.internal:8288" ;;
esac
export INNGEST_UPSTREAM

: "${DASHBOARD_USERNAME:=admin}"
export DASHBOARD_USERNAME

if [ -z "${DASHBOARD_PASSWORD_HASH:-}" ]; then
	if [ -z "${DASHBOARD_PASSWORD:-}" ]; then
		echo "entrypoint: set DASHBOARD_PASSWORD, or DASHBOARD_PASSWORD_HASH to supply your own bcrypt hash" >&2
		exit 1
	fi
	# No Railway variable can compute a bcrypt hash, which is the whole reason
	# this service is built from a repo rather than run as a stock image.
	DASHBOARD_PASSWORD_HASH=$(caddy hash-password --plaintext "$DASHBOARD_PASSWORD")
fi
export DASHBOARD_PASSWORD_HASH

# Keep the plaintext out of the environment Caddy and its children inherit.
unset DASHBOARD_PASSWORD

# The key the dashboard's Send Event button is rewritten onto. INNGEST_EVENT_KEY
# may hold a comma-separated list, and only one key can go in a URL path; take
# the first. With no key configured this stays "dev_key", which makes the
# rewrite a no-op and leaves stock behaviour in place.
DASHBOARD_EVENT_KEY="${INNGEST_EVENT_KEY:-}"
DASHBOARD_EVENT_KEY="${DASHBOARD_EVENT_KEY%%,*}"
: "${DASHBOARD_EVENT_KEY:=dev_key}"
export DASHBOARD_EVENT_KEY

echo "entrypoint: proxying to ${INNGEST_UPSTREAM}, dashboard user ${DASHBOARD_USERNAME}"

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
