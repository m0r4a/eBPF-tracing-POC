# eBPF tracing POC
#
# Each variation recipe takes you from nothing to a working setup: it
# creates the cluster if needed, deploys and seeds the application, starts
# the backend, and applies the agent. Running one twice is harmless.
#
#   just beyla-jaeger     Beyla   -> Jaeger  (in cluster)
#   just beyla-tempo      Beyla   -> Tempo   (on the host)
#   just obi-tempo        OBI     -> Tempo   (on the host)
#   just obi-jaeger       OBI     -> Jaeger  (in cluster)
#   just odigos           Odigos  -> Jaeger  (finish in its UI)
#
# Only one agent at a time. Beyla and OBI attach to the same JVMs, so
# running both makes it impossible to say which produced a given span.
# Each variation removes the other agent before applying its own.
#
# Windows: these recipes need a bash, so run them from WSL2 or Git Bash.
# The eBPF work itself happens inside the minikube node and does not care
# what your machine runs. `just compat` explains the details.

# Recipes shell out to bash, sed and docker compose. On Windows that means
# Git Bash or WSL2; PowerShell alone is not enough.
set windows-shell := ["bash.exe", "-c"]

namespace       := "ebpf-poc"
agent_namespace := "default"
jaeger_endpoint := "http://jaeger.tracing:4317"
tempo_endpoint  := "http://host.minikube.internal:4317"
# Same address without the scheme, which is what the Odigos UI expects.
jaeger_grpc     := "jaeger.tracing:4317"
seed_file       := justfile_directory() / "apps/app_java_17/src/main/resources/data.sql"

# Show the available recipes.
default:
    @just --list --unsorted

# Report what this platform can run, and check the tools are present.
compat:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "just sees:  os={{os()}}  family={{os_family()}}"
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        echo "Environment: WSL2 (${WSL_DISTRO_NAME})"
    else
        echo "Environment: native {{os()}}"
    fi
    echo ""
    echo "Everything eBPF here runs inside the minikube node, which is Linux"
    echo "whatever your machine is. The agents need a node kernel with BTF and"
    echo "uprobes; minikube's node image has both, and so does the WSL2 kernel"
    echo "that Docker Desktop uses on Windows."
    echo ""
    if [ "{{os_family()}}" = "windows" ]; then
        echo "On Windows, run these recipes from WSL2 or Git Bash. They use"
        echo "bash, sed and docker compose, so PowerShell alone will not do."
    fi
    echo "Tools:"
    missing=0
    for c in kubectl minikube docker curl; do
        if command -v "$c" >/dev/null 2>&1; then
            printf "  %-9s present\n" "$c"
        else
            printf "  %-9s MISSING\n" "$c"; missing=1
        fi
    done
    for c in jq odigos; do
        if command -v "$c" >/dev/null 2>&1; then
            printf "  %-9s present (optional)\n" "$c"
        else
            printf "  %-9s absent  (optional)\n" "$c"
        fi
    done
    [ "$missing" -eq 0 ] || echo ""
    [ "$missing" -eq 0 ] || echo "Install the missing required tools before starting."

# Refuses to run unless kubectl is pointed at minikube.
#
# These recipes create and delete whole namespaces. Without this guard a
# stray `just down` would happily do that to whichever cluster your
# context happens to select. Set ALLOW_ANY_CONTEXT=1 to run anyway, for
# instance on a throwaway kubeadm cluster.
_require-minikube:
    #!/usr/bin/env bash
    set -euo pipefail
    ctx=$(kubectl config current-context 2>/dev/null || echo none)
    if [ "${ALLOW_ANY_CONTEXT:-0}" = "1" ]; then
        echo "==> Context check skipped (context: ${ctx})"
        exit 0
    fi
    if [ "${ctx}" != "minikube" ]; then
        echo "kubectl context is '${ctx}', not 'minikube'." >&2
        echo "Refusing to touch namespaces on a cluster this POC did not create." >&2
        echo "Switch context, or re-run with ALLOW_ANY_CONTEXT=1." >&2
        exit 1
    fi

# ---------------------------------------------------------------- base

# Create the minikube cluster, unless it is already running.
cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    if minikube status --format '{{{{.Host}}' 2>/dev/null | grep -q Running; then
        echo "==> Cluster already running"
        # The BPF mount does not survive a stop/start, so redo it.
        minikube ssh -- "sudo mount -t bpf bpf /sys/fs/bpf" 2>/dev/null || true
    else
        echo "==> Creating cluster"
        "{{justfile_directory()}}/minikube.sh" create
    fi

# Deploy the application and wait for it to come up.
deploy: cluster _require-minikube
    @echo "==> Deploying application"
    cd "{{justfile_directory()}}/k8s" && ./deploy.sh

# Load the seed users and orders, unless the database already has them.
seed: deploy
    #!/usr/bin/env bash
    set -euo pipefail
    count=$(kubectl exec -n {{namespace}} deploy/postgres -- \
        psql -U postgres -d appdb -tAc 'select count(*) from users;' 2>/dev/null | tr -d '[:space:]' || echo 0)
    if [ "${count:-0}" -gt 0 ]; then
        echo "==> Database already seeded (${count} users)"
    else
        echo "==> Seeding database"
        kubectl exec -i -n {{namespace}} deploy/postgres -- \
            psql -U postgres -d appdb < "{{seed_file}}"
    fi

# Cluster plus application, with no agent or backend.
up: seed
    @echo ""
    @echo "Application is up. Pick a variation, for example: just obi-tempo"

# ------------------------------------------------------------ backends

# Start Jaeger in the cluster. Does not port forward; use `just ui-jaeger`.
jaeger: cluster _require-minikube
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting Jaeger"
    kubectl apply -f https://raw.githubusercontent.com/odigos-io/simple-demo/main/kubernetes/jaeger.yaml
    kubectl wait --for=condition=available --timeout=300s deployment/jaeger -n tracing

# Start Tempo and Grafana on the host.
tempo:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Starting Tempo and Grafana"
    cd "{{justfile_directory()}}/backends/tempo-grafana"
    docker compose up -d
    for i in $(seq 1 30); do
        if curl -sf -m 2 http://localhost:3200/ready >/dev/null 2>&1; then
            echo "Tempo ready"; exit 0
        fi
        sleep 2
    done
    echo "Tempo did not report ready in 60s; check 'docker compose logs tempo'" >&2

# ---------------------------------------------------------- variations

# Beyla, exporting to Jaeger in the cluster.
beyla-jaeger: seed jaeger
    @just _agent beyla "{{jaeger_endpoint}}"
    @just _where jaeger

# Beyla, exporting to Tempo on the host.
beyla-tempo: seed tempo
    @just _agent beyla "{{tempo_endpoint}}"
    @just _where tempo

# OBI, exporting to Tempo on the host.
obi-tempo: seed tempo
    @just _agent obi "{{tempo_endpoint}}"
    @just _where tempo

# OBI, exporting to Jaeger in the cluster.
obi-jaeger: seed jaeger
    @just _agent obi "{{jaeger_endpoint}}"
    @just _where jaeger

# Install Odigos and start Jaeger. Selecting workloads is a UI step.
odigos: seed jaeger
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v odigos >/dev/null 2>&1; then
        echo "odigos CLI not found. See instrumentation/odigos/README.md" >&2
        exit 1
    fi
    just _agent-rm
    echo "==> Installing Odigos"
    odigos install
    echo ""
    echo "Now run 'odigos ui', select java8-gateway and java17-service,"
    echo "and add a Jaeger destination at {{jaeger_grpc}}"
    echo "Selecting workloads restarts them, so give the pods a moment."

# Applies an agent's manifests with its export endpoint rewritten.
_agent name endpoint: _require-minikube
    #!/usr/bin/env bash
    set -euo pipefail
    just _agent-rm
    dir="{{justfile_directory()}}/instrumentation/{{name}}"
    echo "==> Applying {{name}} -> {{endpoint}}"
    kubectl apply -f "$dir/rbac.yaml"
    # Rewrite the single endpoint line rather than editing the file in
    # the repo, so switching backends leaves no diff behind.
    sed 's|^\( *\)endpoint: .*|\1endpoint: {{endpoint}}|' "$dir"/*-config.yaml | kubectl apply -f -
    kubectl apply -f "$dir"/{{ if name == "obi" { "OBI.yaml" } else { "beyla.yaml" } }}
    if ! kubectl rollout status daemonset/{{name}} -n {{agent_namespace}} --timeout=180s; then
        echo ""
        echo "{{name}} did not become ready. The usual cause is the BPF mount:" >&2
        echo "  minikube ssh -- 'sudo mount -t bpf bpf /sys/fs/bpf'" >&2
        echo "Then: kubectl describe pod -l app={{name}} -n {{agent_namespace}}" >&2
        exit 1
    fi

# Removes whichever agent is currently applied.
_agent-rm: _require-minikube
    #!/usr/bin/env bash
    set -euo pipefail
    for a in beyla obi; do
        if kubectl get daemonset "$a" -n {{agent_namespace}} >/dev/null 2>&1; then
            echo "==> Removing $a"
            kubectl delete -f "{{justfile_directory()}}/instrumentation/$a" --ignore-not-found >/dev/null 2>&1 || true
        fi
    done

# Prints where to look once an agent is running.
_where backend:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    if [ "{{backend}}" = "jaeger" ]; then
        echo "Jaeger UI:  just ui-jaeger  (then http://localhost:16686)"
    else
        echo "Grafana:    http://localhost:3000  (admin/admin)"
    fi
    echo "Traffic:    just traffic 5"
    echo ""
    echo "Sampling is 0.5, so half the traces are dropped by design."

# ----------------------------------------------------------- day to day

# One request per endpoint.
test:
    cd "{{justfile_directory()}}/k8s" && ./test.sh

# Generate traffic for N minutes.
traffic minutes="1":
    cd "{{justfile_directory()}}/k8s" && ./traffic.sh --time {{minutes}}

# Show application and agent state.
status:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}/k8s" && ./deploy.sh status
    echo "==> Agents"
    kubectl get daemonset -n {{agent_namespace}} -l 'app in (beyla,obi)' 2>/dev/null || echo "None running"
    echo "==> Backends"
    kubectl get deployment jaeger -n tracing 2>/dev/null || echo "Jaeger not running"
    docker compose -f "{{justfile_directory()}}/backends/tempo-grafana/compose.yml" ps 2>/dev/null || true

# Follow the running agent's logs.
logs:
    #!/usr/bin/env bash
    set -euo pipefail
    for a in beyla obi; do
        if kubectl get daemonset "$a" -n {{agent_namespace}} >/dev/null 2>&1; then
            exec kubectl logs -f -l app="$a" -n {{agent_namespace}}
        fi
    done
    echo "No agent running" >&2

# Port forward the Jaeger UI. Holds the terminal open.
ui-jaeger:
    @echo "Jaeger UI on http://localhost:16686 (Ctrl-C to stop)"
    kubectl port-forward -n tracing svc/jaeger 16686:16686

# ------------------------------------------------------------- teardown

# Remove the agent, leaving the application and backends up.
clean-agent: _agent-rm

# Stop the backends.
clean-backends: _require-minikube
    #!/usr/bin/env bash
    set -euo pipefail
    docker compose -f "{{justfile_directory()}}/backends/tempo-grafana/compose.yml" down 2>/dev/null || true
    kubectl delete namespace tracing --ignore-not-found

# Remove agent, backends and application, keeping the cluster.
down: _require-minikube clean-agent clean-backends
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl delete namespace {{namespace}} --ignore-not-found

# Delete the whole cluster and stop the host backends.
destroy: clean-backends
    "{{justfile_directory()}}/minikube.sh" destroy
