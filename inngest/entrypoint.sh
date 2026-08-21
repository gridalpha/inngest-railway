#!/bin/sh
# Boot wrapper for `inngest start` on Railway.
#
# Everything here is a default, applied only when the operator has not set the
# variable, so a template deploy needs none of them and a technical user can
# still override every one.
set -eu

# The CLI binds localhost by default, which Railway's edge and the private
# network both cannot reach.
: "${INNGEST_HOST:=0.0.0.0}"

# Railway probes the port named by PORT; keep the app's listener on the same one.
: "${INNGEST_PORT:=${PORT:-8288}}"

# The pool ships at 100 open connections and Railway's managed Postgres accepts
# 100 in total, so the shipped default leaves no headroom for a second replica,
# for psql, or for the database's own reserved superuser slots.
: "${INNGEST_POSTGRES_MAX_OPEN_CONNS:=25}"
: "${INNGEST_POSTGRES_MAX_IDLE_CONNS:=5}"

export INNGEST_HOST INNGEST_PORT
export INNGEST_POSTGRES_MAX_OPEN_CONNS INNGEST_POSTGRES_MAX_IDLE_CONNS

# Connect's gateway and executor tell their peers where to reach them over gRPC,
# and the CLI defaults both to 127.0.0.1. Railway routes only IPv6 between
# services, so with more than one replica each container would publish an
# address that resolves to itself and cross-replica Connect traffic would hang.
# Publish this container's own ULA address instead. A single replica behaves
# identically either way, so this costs nothing until the service is scaled.
if [ -z "${INNGEST_CONNECT_GATEWAY_GRPC_IP:-}" ] && [ -r /proc/net/if_inet6 ]; then
    ula=""
    while read -r addr _ifindex _prefixlen scope _flags _dev; do
        # Column 4 is the scope; 00 is global. Prefer the fd00::/8 ULA, which is
        # the address peers in this environment actually route to.
        case "${scope}:${addr}" in
            00:fd*) ula="$addr"; break ;;
        esac
    done < /proc/net/if_inet6

    if [ -n "$ula" ]; then
        # /proc reports the address as 32 undelimited hex digits; net.ParseIP
        # wants the colon-grouped form, and rejects it if it carries brackets.
        ula=$(printf '%s' "$ula" | sed -E 's/.{4}/&:/g; s/:$//')
        INNGEST_CONNECT_GATEWAY_GRPC_IP="$ula"
        INNGEST_CONNECT_EXECUTOR_GRPC_IP="${INNGEST_CONNECT_EXECUTOR_GRPC_IP:-$ula}"
        export INNGEST_CONNECT_GATEWAY_GRPC_IP INNGEST_CONNECT_EXECUTOR_GRPC_IP
        echo "entrypoint: connect gRPC peers will reach this replica at [${ula}]"
    fi
fi

echo "entrypoint: starting inngest on ${INNGEST_HOST}:${INNGEST_PORT}"
exec inngest start "$@"
