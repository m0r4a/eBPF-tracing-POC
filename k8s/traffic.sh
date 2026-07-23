#!/bin/bash

set -o pipefail

NAMESPACE="ebpf-poc"
SERVICE="java8-gateway"
DURATION_MIN=1

uso() {
    echo "Uso: $0 --time|-t <minutos>"
    exit 1
}

# Parseo de argumentos

while [[ $# -gt 0 ]]; do
    case "$1" in
    --time | -t)
        [ -z "${2:-}" ] && uso
        DURATION_MIN="$2"
        shift 2
        ;;
    *)
        uso
        ;;
    esac
done

if ! [[ "$DURATION_MIN" =~ ^[0-9]+$ ]]; then
    echo "Error: --time debe ser un entero"
    exit 1
fi

DURATION_SEC=$((DURATION_MIN * 60))

# Obtener URL del Gateway

echo "Obteniendo URL del gateway..."
GATEWAY_URL=$(minikube service "$SERVICE" -n "$NAMESPACE" --url)

if [ -z "$GATEWAY_URL" ]; then
    echo "Error: No se pudo obtener la URL"
    exit 1
fi

echo "Gateway URL: $GATEWAY_URL"
echo "Duración: $DURATION_MIN minuto(s)"
echo ""

# Endpoints

ENDPOINTS=(
    "GET:/api/health"
    "POST:/api/users"
    "GET:/api/users/1"
    "GET:/api/users/2"
    "GET:/api/orders/1"
    "GET:/api/orders/3"
)

generar_payload_usuario() {
    local id=$((RANDOM % 10000))
    echo "{\"name\":\"Usuario$id\",\"email\":\"usuario$id@example.com\"}"
}

# Loop principal

echo "Generando tráfico..."
START_TIME=$(date +%s)

iter=0
ok=0
err=0

while true; do
    iter=$((iter + 1))

    ahora=$(date +%s)
    transcurrido=$((ahora - START_TIME))

    if [ "$transcurrido" -ge "$DURATION_SEC" ]; then
        echo "Tiempo alcanzado, saliendo"
        break
    fi

    choice=${ENDPOINTS[$RANDOM % ${#ENDPOINTS[@]}]}
    metodo="${choice%%:*}"
    path="${choice##*:}"

    ts=$(date +"%H:%M:%S")

    if [ "$metodo" = "POST" ]; then
        payload=$(generar_payload_usuario)
        code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "$GATEWAY_URL$path" \
            -H "Content-Type: application/json" \
            -d "$payload")
    else
        code=$(curl -s -o /dev/null -w "%{http_code}" \
            "$GATEWAY_URL$path")
    fi

    if [[ "$code" =~ ^2 ]]; then
        ok=$((ok + 1))
        status="OK"
    else
        err=$((err + 1))
        status="ERR"
    fi

    printf "[%s] #%04d %-4s %-20s -> %s | OK=%d ERR=%d\n" \
        "$ts" "$iter" "$metodo" "$path" "$code" "$ok" "$err"

    # Sleep 100–600 ms
    sleep "0.$(printf "%03d" $((RANDOM % 500 + 100)))"
done

# Resumen final

echo ""
echo "==== RESUMEN ===="
echo "Iteraciones: $iter"
echo "OK: $ok"
echo "Errores: $err"
