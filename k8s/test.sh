#!/bin/bash
#
# One request per endpoint, then a short burst to show the injected
# errors, then the last transaction lines from both services.
#
# Two things to expect. The create-user step posts a fixed address and
# the email column is unique, so it succeeds once and returns 500 on
# every later run against the same database. And the reads only return
# data if you seeded the database first; see the README.
#
# Uses `minikube service`, so it only works on minikube.

set -e

NAMESPACE="ebpf-poc"
SERVICE="java8-gateway"

echo "Getting the gateway URL..."
GATEWAY_URL=$(minikube service $SERVICE -n $NAMESPACE --url 2>/dev/null)

if [ -z "$GATEWAY_URL" ]; then
    echo "Error: could not get the service URL"
    exit 1
fi

echo "Gateway URL: $GATEWAY_URL"
echo ""

test_endpoint() {
    local name=$1
    local method=$2
    local path=$3
    local data=$4

    echo "[$name]"
    if [ -z "$data" ]; then
        response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$GATEWAY_URL$path")
    else
        response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X "$method" "$GATEWAY_URL$path" \
            -H "Content-Type: application/json" \
            -d "$data")
    fi

    http_code=$(echo "$response" | grep "HTTP_CODE" | cut -d':' -f2)
    body=$(echo "$response" | sed '/HTTP_CODE/d')

    if command -v jq &>/dev/null; then
        echo "$body" | jq -C .
    else
        echo "$body"
    fi

    echo "Status: $http_code"
    echo ""
}

test_endpoint "Health Check" "GET" "/api/health"

test_endpoint "Create User" "POST" "/api/users" \
    '{"name":"Test User","email":"test@example.com"}'

test_endpoint "Get User 1" "GET" "/api/users/1"

test_endpoint "Get User 2" "GET" "/api/users/2"

test_endpoint "Get Orders User 1" "GET" "/api/orders/1"

test_endpoint "Get Orders User 3" "GET" "/api/orders/3"

# Both services fail a percentage of requests on purpose, so a few
# errors here are the expected result, not a broken deployment.
echo "Testing error injection (10 requests)..."
success=0
errors=0
for i in {1..10}; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$GATEWAY_URL/api/users/1")
    if [ "$http_code" = "200" ]; then
        ((success++))
    else
        ((errors++))
    fi
done
echo "Success: $success | Errors: $errors"
echo ""

echo "Recent Gateway Logs (last 15 transactions):"
kubectl logs -l app=java8-gateway -n $NAMESPACE --tail=50 | grep "|" | tail -15

echo ""
echo "Recent Service Logs (last 15 transactions):"
kubectl logs -l app=java17-service -n $NAMESPACE --tail=50 | grep "|" | tail -15
