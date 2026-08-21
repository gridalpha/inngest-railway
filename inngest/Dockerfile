# Inngest publishes a working image; the only gap is a boot-time step, so this
# adds one layer rather than rebuilding upstream's Go monorepo.
FROM inngest/inngest:latest

COPY inngest/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# The image ships CMD ["inngest"] with no ENTRYPOINT, so an unmodified container
# prints the CLI's help and exits. The entrypoint supplies the `start` subcommand.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
