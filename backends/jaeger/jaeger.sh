#!/bin/bash
#
# Installs Jaeger in the cluster and port forwards its UI.
#
# The quickest backend to stand up, which is why Beyla and Odigos both
# default to it. Storage is in memory, so restarting the pod loses every
# trace.
#
# This does not return: the port forward holds the terminal open, so give
# it one of its own. Ctrl-C stops the forward only, Jaeger keeps running.

# Applied straight from the Odigos demo repo, so this needs network
# access. Lands in the `tracing` namespace.
kubectl apply -f https://raw.githubusercontent.com/odigos-io/simple-demo/main/kubernetes/jaeger.yaml

# Waits on every deployment in the cluster, not just Jaeger. Anything
# else unhealthy will hold this up for the full timeout.
kubectl wait --for=condition=available --timeout=300s deployment --all --all-namespaces

echo ""
echo "############################################"
echo ""
echo "This window will stay open: it is port forwarding the Jaeger UI."
echo "Open http://localhost:16686, and press Ctrl-C here when you are done."
echo ""
echo 'In Odigos, set "Jaeger OTLP gRPC Endpoint" to "jaeger.tracing:4317"'

# UI on http://localhost:16686. The OTLP endpoint the agents send to is
# jaeger.tracing:4317, which is reached in-cluster and not through this.
kubectl port-forward -n tracing svc/jaeger 16686:16686
