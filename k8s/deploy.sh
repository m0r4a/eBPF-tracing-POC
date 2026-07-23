#!/bin/bash

set -e

NAMESPACE="ebpf-poc"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}==> $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

wait_for_pods() {
    local label=$1
    local timeout=${2:-120}
    local component=$3

    print_status "Esperando a que $component esté listo (timeout: ${timeout}s)..."

    if kubectl wait --for=condition=ready pod -l "$label" -n "$NAMESPACE" --timeout="${timeout}s" 2>&1 | grep -v "no matching resources found"; then
        print_success "$component listo"
        return 0
    else
        print_error "$component no está listo después de ${timeout}s"
        print_warning "Estado actual de $component:"
        kubectl get pods -l "$label" -n "$NAMESPACE" 2>/dev/null || echo "No hay pods"
        return 1
    fi
}

deploy() {
    echo ""
    print_status "Desplegando eBPF POC en Kubernetes"
    echo ""

    # Namespace
    print_status "[1/4] Creando namespace..."
    kubectl apply -f namespace/ >/dev/null 2>&1
    print_success "Namespace configurado"
    echo ""

    # PostgreSQL
    print_status "[2/4] Desplegando PostgreSQL..."
    kubectl apply -f database/ >/dev/null 2>&1
    wait_for_pods "app=postgres" 120 "PostgreSQL"
    echo ""

    # Java 17 Service
    print_status "[3/4] Desplegando Java 17 Service..."
    kubectl apply -f java17-service/ >/dev/null 2>&1
    wait_for_pods "app=java17-service" 120 "Java 17 Service"
    echo ""

    # Java 8 Gateway
    print_status "[4/4] Desplegando Java 8 Gateway..."
    kubectl apply -f java8-gateway/ >/dev/null 2>&1
    wait_for_pods "app=java8-gateway" 120 "Java 8 Gateway"
    echo ""

    # Resumen
    print_success "Despliegue completado"
    echo ""
    print_status "Estado del cluster:"
    kubectl get pods -n "$NAMESPACE"
    echo ""

    # Obtener URL
    if command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
        print_status "Para acceder al gateway ejecuta:"
        echo "  export GATEWAY_URL=\$(minikube service java8-gateway -n $NAMESPACE --url)"
        echo ""
        print_status "O ejecuta el script de pruebas:"
        echo "  ./test.sh"
    else
        print_status "Para obtener la URL del gateway:"
        echo "  kubectl get svc java8-gateway -n $NAMESPACE"
    fi
    echo ""
}

destroy() {
    echo ""
    print_status "Eliminando eBPF POC de Kubernetes"
    echo ""

    # Verificar si el namespace existe
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_warning "El namespace '$NAMESPACE' no existe"
        exit 0
    fi

    # Confirmar eliminación
    read -p "¿Estás seguro de eliminar todo el namespace '$NAMESPACE'? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Operación cancelada"
        exit 0
    fi

    print_status "Eliminando recursos..."

    # Eliminar deployments primero para detener los pods
    kubectl delete deployments --all -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

    # Eliminar namespace
    kubectl delete namespace "$NAMESPACE" --timeout=60s 2>/dev/null || true

    print_success "Eliminación completada"
    echo ""
}

status() {
    echo ""
    print_status "Estado de eBPF POC"
    echo ""

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_warning "El namespace '$NAMESPACE' no existe"
        print_status "Ejecuta './deploy.sh' para desplegar"
        exit 0
    fi

    print_status "Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""

    print_status "Servicios:"
    kubectl get svc -n "$NAMESPACE"
    echo ""

    print_status "Deployments:"
    kubectl get deployments -n "$NAMESPACE"
    echo ""

    local all_ready=true

    for app in postgres java17-service java8-gateway; do
        if kubectl get pods -l app="$app" -n "$NAMESPACE" &>/dev/null; then
            if kubectl wait --for=condition=ready pod -l app="$app" -n "$NAMESPACE" --timeout=1s &>/dev/null; then
                print_success "$app: Ready"
            else
                print_warning "$app: Not Ready"
                all_ready=false
            fi
        fi
    done

    echo ""
    if [ "$all_ready" = true ]; then
        print_success "Todos los componentes están listos"
    else
        print_warning "Algunos componentes no están listos"
    fi
    echo ""
}

logs() {
    local component=${1:-all}

    echo ""
    print_status "Logs de eBPF POC"
    echo ""

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "El namespace '$NAMESPACE' no existe"
        exit 1
    fi

    case $component in
    gateway | java8)
        print_status "Logs de Java 8 Gateway:"
        kubectl logs -l app=java8-gateway -n "$NAMESPACE" --tail=50
        ;;
    service | java17)
        print_status "Logs de Java 17 Service:"
        kubectl logs -l app=java17-service -n "$NAMESPACE" --tail=50
        ;;
    db | postgres | database)
        print_status "Logs de PostgreSQL:"
        kubectl logs -l app=postgres -n "$NAMESPACE" --tail=50
        ;;
    all | *)
        print_status "Logs de Java 8 Gateway (últimas transacciones):"
        kubectl logs -l app=java8-gateway -n "$NAMESPACE" --tail=100 | grep "|" | tail -20 || print_warning "No hay logs de transacciones"
        echo ""
        print_status "Logs de Java 17 Service (últimas transacciones):"
        kubectl logs -l app=java17-service -n "$NAMESPACE" --tail=100 | grep "|" | tail -20 || print_warning "No hay logs de transacciones"
        echo ""
        print_status "Logs de PostgreSQL:"
        kubectl logs -l app=postgres -n "$NAMESPACE" --tail=10
        ;;
    esac
    echo ""
}

usage() {
    cat <<EOF
Uso: $0 [COMANDO]

Comandos:
  deploy, up              Despliega toda la aplicación (default)
  destroy, down, rm       Elimina toda la aplicación
  status, st              Muestra el estado actual
  logs [componente]       Muestra logs (gateway|service|database|all)
  help, -h, --help        Muestra esta ayuda

Ejemplos:
  $0                      # Despliega la aplicación
  $0 deploy               # Despliega la aplicación
  $0 destroy              # Elimina la aplicación
  $0 status               # Muestra el estado
  $0 logs gateway         # Muestra logs del gateway
  $0 logs                 # Muestra logs de todos los componentes

EOF
}

# Main
case "${1:-deploy}" in
deploy | up | "")
    deploy
    ;;
destroy | down | rm | remove | delete)
    destroy
    ;;
status | st | state)
    status
    ;;
logs | log)
    logs "${2:-all}"
    ;;
help | -h | --help)
    usage
    ;;
*)
    print_error "Comando desconocido: $1"
    echo ""
    usage
    exit 1
    ;;
esac
