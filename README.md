# Inngest on Railway

Deployment files for running the [Inngest](https://github.com/inngest/inngest)
server — durable functions, queues and scheduling — on Railway, behind a Caddy
gateway that closes the parts of the self-hosted server upstream leaves open.

Two images, both a single layer on top of a published one:

| Directory  | Base                  | Role |
|------------|-----------------------|------|
| `inngest/` | `inngest/inngest:latest` | The Inngest server: event API, executor, dashboard, Connect gateway. Private. |
| `gateway/` | `caddy:2-alpine`      | Public entry point. Password-protects the dashboard, passes SDK traffic through. |

Both build from the repository root. Select the Dockerfile per service with
`RAILWAY_DOCKERFILE_PATH=inngest/Dockerfile` or `gateway/Dockerfile`.

## Why a gateway

Self-hosted Inngest authenticates SDK traffic — the event key is in the
`/e/{key}` path, and `/v1`, `/v2` and `/fn/register` sit behind a signing-key
middleware — but it ships no authentication for anything a browser reaches. The
dashboard, the GraphQL API at `/v0/gql` and its playground, the pprof handlers
under `/debug`, the Prometheus endpoint at `/metrics` and `/invoke/{slug}` all
answer anonymously. Upstream's own comment on the invoke handler reads
`// XXX: In OSS self hosting, check signing keys here.`

So the Inngest service takes no public domain. The gateway does, and splits the
surface by path: SDK routes pass straight through to the key checks that already
exist, everything else needs HTTP basic auth. Basic auth is the right shape for
the browser half specifically — the browser replays it on the dashboard's own
same-origin XHR, so one rule covers the UI and the GraphQL API behind it.

## Variables

Nothing here is required at deploy time except a dashboard password; every other
value has a working default in the entrypoints.

### `gateway`

| Variable | Default | Purpose |
|---|---|---|
| `DASHBOARD_PASSWORD` | — | Dashboard password. Hashed with bcrypt at boot; the plaintext is dropped from the environment before Caddy starts. |
| `DASHBOARD_USERNAME` | `admin` | Dashboard username. |
| `DASHBOARD_PASSWORD_HASH` | derived | Set this instead of `DASHBOARD_PASSWORD` to supply your own `caddy hash-password` output. |
| `INNGEST_UPSTREAM` | `inngest.railway.internal:8288` | Where the Inngest server listens. Defaulted on the value's shape, so an empty cross-service reference cannot bake a broken upstream. |
| `PORT` | set by Railway | Listen port. |

### `inngest`

| Variable | Default | Purpose |
|---|---|---|
| `INNGEST_SIGNING_KEY` | — | Hex string, even number of characters. Must match the SDK's. Stable across restarts. |
| `INNGEST_EVENT_KEY` | — | Key apps put in the `/e/{key}` event URL. Comma-separate to allow several. |
| `INNGEST_POSTGRES_URI` | — | `postgres://` or `postgresql://`. Configuration and run history. Migrations run at boot. |
| `INNGEST_REDIS_URI` | — | `redis://`. Queue, run state and realtime pub/sub. |
| `INNGEST_HOST` | `0.0.0.0` | The CLI binds localhost otherwise, which nothing on Railway can reach. |
| `INNGEST_PORT` | `$PORT`, else `8288` | API, dashboard and event listener. |
| `INNGEST_POSTGRES_MAX_OPEN_CONNS` | `25` | Upstream ships `100`, which is Railway's managed Postgres `max_connections` in its entirety. |
| `INNGEST_POSTGRES_MAX_IDLE_CONNS` | `5` | |
| `INNGEST_CONNECT_GATEWAY_GRPC_IP` | this container's ULA | Address peers use to reach this replica's Connect gateway. |
| `INNGEST_CONNECT_EXECUTOR_GRPC_IP` | this container's ULA | Same, for the executor. |

Any other `inngest start` flag works as a variable: uppercase it, replace
hyphens with underscores, prefix `INNGEST_` — `--queue-workers` is
`INNGEST_QUEUE_WORKERS`, `--log-level` is `INNGEST_LOG_LEVEL`.

## Connect

Inngest's Connect transport has workers hold a WebSocket to the server rather
than serving an HTTP endpoint. It works between services **inside the same
Railway project**: the server advertises its gateway as
`ws://<host>:8289/v0/connect`, derived from the `Host` of the request that
started the session, and a private caller reaching `inngest.railway.internal`
gets a private address back.

It does not work from outside the project. The advertised URL is always plain
`ws://` on port 8289, and Railway's edge serves TLS on 443 only, so no domain
can carry it. Apps outside the project should use an HTTP `serve()` endpoint,
which is Inngest's default transport anyway.

## Replicas

The server is built to scale horizontally against shared Postgres and Redis, and
cron scheduling deduplicates through the queue rather than running per process,
so raising replicas does not duplicate scheduled runs.

The one thing that needs help is Connect: its gateway and executor publish a
gRPC address to their peers, and the CLI defaults both to `127.0.0.1`, so every
replica would advertise itself. The entrypoint reads this container's own
`fd00::/8` address out of `/proc/net/if_inet6` and publishes that instead, which
is the address family Railway actually routes between services.
