#!/bin/bash
#
# Generates continuous traffic for a given number of minutes, so there is
# something to watch arrive while you have a trace UI open.
#
# Unlike test.sh this can be run repeatedly: the user payloads carry
# random emails, so they do not collide with the unique constraint.
#
# Uses `minikube service`, so it only works on minikube.

set -o pipefail

NAMESPACE="ebpf-poc"
SERVICE="java8-gateway"
DURATION_MIN=1

usage() {
    echo "Usage: $0 --time|-t <minutes>"
    exit 1
}

# Argument parsing

while [[ $# -gt 0 ]]; do
    case "$1" in
    --time | -t)
        [ -z "${2:-}" ] && usage
        DURATION_MIN="$2"
        shift 2
        ;;
    *)
        usage
        ;;
    esac
done

if ! [[ "$DURATION_MIN" =~ ^[0-9]+$ ]]; then
    echo "Error: --time must be an integer"
    exit 1
fi

DURATION_SEC=$((DURATION_MIN * 60))

# Gateway URL

echo "Getting the gateway URL..."
GATEWAY_URL=$(minikube service "$SERVICE" -n "$NAMESPACE" --url)

if [ -z "$GATEWAY_URL" ]; then
    echo "Error: could not get the URL"
    exit 1
fi

echo "Gateway URL: $GATEWAY_URL"
echo "Duration: $DURATION_MIN minute(s)"
echo ""

# Endpoints, picked from at random.
#
# /api/health is answered by the gateway itself and never reaches the
# Java 17 service, so roughly a sixth of this load produces single-hop
# traces with no database span.

ENDPOINTS=(
    "GET:/api/health"
    "POST:/api/users"
    "GET:/api/users/1"
    "GET:/api/users/2"
    "GET:/api/orders/1"
    "GET:/api/orders/3"
)

# Random email per call, so repeated runs do not hit the unique
# constraint on users.email.
generate_user_payload() {
    local id=$((RANDOM % 10000))
    echo "{\"name\":\"User$id\",\"email\":\"user$id@example.com\"}"
}

# Main loop

echo "Generating traffic..."
START_TIME=$(date +%s)

iter=0
ok=0
err=0

while true; do
    iter=$((iter + 1))

    now=$(date +%s)
    elapsed=$((now - START_TIME))

    if [ "$elapsed" -ge "$DURATION_SEC" ]; then
        echo "Time is up, stopping"
        break
    fi

    choice=${ENDPOINTS[$RANDOM % ${#ENDPOINTS[@]}]}
    method="${choice%%:*}"
    path="${choice##*:}"

    ts=$(date +"%H:%M:%S")

    if [ "$method" = "POST" ]; then
        payload=$(generate_user_payload)
        code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "$GATEWAY_URL$path" \
            -H "Content-Type: application/json" \
            -d "$payload")
    else
        code=$(curl -s -o /dev/null -w "%{http_code}" \
            "$GATEWAY_URL$path")
    fi

    # Non-2xx is expected here: both services fail a percentage of
    # requests on purpose.
    if [[ "$code" =~ ^2 ]]; then
        ok=$((ok + 1))
    else
        err=$((err + 1))
    fi

    printf "[%s] #%04d %-4s %-20s -> %s | OK=%d ERR=%d\n" \
        "$ts" "$iter" "$method" "$path" "$code" "$ok" "$err"

    # 100 to 600 ms between requests. Enough to look like traffic
    # without flooding a laptop-sized cluster.
    sleep "0.$(printf "%03d" $((RANDOM % 500 + 100)))"
done

# Summary

echo ""
echo "==== SUMMARY ===="
echo "Iterations: $iter"
echo "OK: $ok"
echo "Errors: $err"
