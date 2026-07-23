#!/bin/bash
#
# Deploys, inspects and removes the application in the ebpf-poc namespace.
#
# Run from inside k8s/. The manifest paths are relative to this directory.
#
# Deploying is only half of setup: the database comes up empty and needs
# seeding before anything returns data. See the README.

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

# Blocks until pods matching a label are ready, so the next component is
# not deployed against a database that is still starting.
wait_for_pods() {
    local label=$1
    local timeout=${2:-120}
    local component=$3

    print_status "Waiting for $component to be ready (timeout: ${timeout}s)..."

    if kubectl wait --for=condition=ready pod -l "$label" -n "$NAMESPACE" --timeout="${timeout}s" 2>&1 | grep -v "no matching resources found"; then
        print_success "$component ready"
        return 0
    else
        print_error "$component not ready after ${timeout}s"
        print_warning "Current state of $component:"
        kubectl get pods -l "$label" -n "$NAMESPACE" 2>/dev/null || echo "No pods found"
        return 1
    fi
}

# Order matters: the Java 17 service needs the database, and the gateway
# needs the Java 17 service.
deploy() {
    echo ""
    print_status "Deploying eBPF POC to Kubernetes"
    echo ""

    # Namespace
    print_status "[1/4] Creating namespace..."
    kubectl apply -f namespace/ >/dev/null 2>&1
    print_success "Namespace ready"
    echo ""

    # PostgreSQL
    print_status "[2/4] Deploying PostgreSQL..."
    kubectl apply -f database/ >/dev/null 2>&1
    wait_for_pods "app=postgres" 120 "PostgreSQL"
    echo ""

    # Java 17 Service
    print_status "[3/4] Deploying Java 17 Service..."
    kubectl apply -f java17-service/ >/dev/null 2>&1
    wait_for_pods "app=java17-service" 120 "Java 17 Service"
    echo ""

    # Java 8 Gateway
    print_status "[4/4] Deploying Java 8 Gateway..."
    kubectl apply -f java8-gateway/ >/dev/null 2>&1
    wait_for_pods "app=java8-gateway" 120 "Java 8 Gateway"
    echo ""

    # Summary
    print_success "Deployment complete"
    echo ""
    print_status "Cluster state:"
    kubectl get pods -n "$NAMESPACE"
    echo ""

    # Show how to reach the gateway
    if command -v minikube &>/dev/null && minikube status &>/dev/null 2>&1; then
        print_status "To reach the gateway, run:"
        echo "  export GATEWAY_URL=\$(minikube service java8-gateway -n $NAMESPACE --url)"
        echo ""
        print_status "Or run the test script:"
        echo "  ./test.sh"
    else
        print_status "To get the gateway URL:"
        echo "  kubectl get svc java8-gateway -n $NAMESPACE"
    fi
    echo ""
}

destroy() {
    echo ""
    print_status "Removing eBPF POC from Kubernetes"
    echo ""

    # Nothing to do if it was never deployed
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_warning "Namespace '$NAMESPACE' does not exist"
        exit 0
    fi

    # Deleting the namespace is not reversible, so make it deliberate.
    read -p "Delete the entire '$NAMESPACE' namespace? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Cancelled"
        exit 0
    fi

    print_status "Removing resources..."

    # Deployments first, so the pods are gone before the namespace
    # deletion starts tearing their dependencies out from under them.
    kubectl delete deployments --all -n "$NAMESPACE" --timeout=30s 2>/dev/null || true

    # Takes the PVC with it, so the seed data goes too.
    kubectl delete namespace "$NAMESPACE" --timeout=60s 2>/dev/null || true

    print_success "Removal complete"
    echo ""
}

status() {
    echo ""
    print_status "eBPF POC status"
    echo ""

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_warning "Namespace '$NAMESPACE' does not exist"
        print_status "Run './deploy.sh' to deploy it"
        exit 0
    fi

    print_status "Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""

    print_status "Services:"
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
        print_success "All components are ready"
    else
        print_warning "Some components are not ready"
    fi
    echo ""
}

logs() {
    local component=${1:-all}

    echo ""
    print_status "eBPF POC logs"
    echo ""

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi

    case $component in
    gateway | java8)
        print_status "Java 8 Gateway logs:"
        kubectl logs -l app=java8-gateway -n "$NAMESPACE" --tail=50
        ;;
    service | java17)
        print_status "Java 17 Service logs:"
        kubectl logs -l app=java17-service -n "$NAMESPACE" --tail=50
        ;;
    db | postgres | database)
        print_status "PostgreSQL logs:"
        kubectl logs -l app=postgres -n "$NAMESPACE" --tail=50
        ;;
    # No component given: filter both applications down to their
    # transaction lines, which are the pipe-delimited ones.
    all | *)
        print_status "Java 8 Gateway (recent transactions):"
        kubectl logs -l app=java8-gateway -n "$NAMESPACE" --tail=100 | grep "|" | tail -20 || print_warning "No transaction logs yet"
        echo ""
        print_status "Java 17 Service (recent transactions):"
        kubectl logs -l app=java17-service -n "$NAMESPACE" --tail=100 | grep "|" | tail -20 || print_warning "No transaction logs yet"
        echo ""
        print_status "PostgreSQL logs:"
        kubectl logs -l app=postgres -n "$NAMESPACE" --tail=10
        ;;
    esac
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 [COMMAND]

Commands:
  deploy, up              Deploy the whole application (default)
  destroy, down, rm       Remove the whole application
  status, st              Show the current state
  logs [component]        Show logs (gateway|service|database|all)
  help, -h, --help        Show this help

Examples:
  $0                      # Deploy the application
  $0 destroy              # Remove the application
  $0 status               # Show the current state
  $0 logs gateway         # Show gateway logs
  $0 logs                 # Show logs for every component

After deploying, the database is empty and needs seeding before any
endpoint returns data. See the README for the command.

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
    print_error "Unknown command: $1"
    echo ""
    usage
    exit 1
    ;;
esac
