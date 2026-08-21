# Stock Caddy in front of Inngest. `reverse_proxy` re-resolves its upstream per
# request, so a redeploy of the Inngest service never leaves a stale address
# behind, and Caddy sizes its own worker pool from the cgroup rather than the
# 48-core host.
FROM caddy:2-alpine

COPY gateway/Caddyfile /etc/caddy/Caddyfile
COPY gateway/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
