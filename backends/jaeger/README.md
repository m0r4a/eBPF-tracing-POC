# Jaeger

Jaeger in the cluster, applied straight from the Odigos demo repository. It is the quickest backend
to get running, which is why Beyla and Odigos both default to it.

```bash
./jaeger.sh
```

The script pulls the manifest from GitHub, so it needs network access. Then it waits for every
deployment in the cluster to be available and holds the terminal open port forwarding the UI to
http://localhost:16686. It does not exit, so give it its own terminal. Ctrl-C stops the port forward
only, Jaeger keeps running.

Jaeger goes into the `tracing` namespace. Its OTLP gRPC endpoint is `jaeger.tracing:4317`, which is
what you type into the Odigos UI and what `instrumentation/beyla/beyla-config.yaml` already points
at.

To get the UI back later without rerunning the script:

```bash
kubectl port-forward -n tracing svc/jaeger 16686:16686
```

One thing to watch: the script runs `kubectl wait ... --all --all-namespaces`, so it waits on every
deployment in the cluster, not just Jaeger. If anything else is unhealthy it will sit there for the
full 300 seconds before giving up.

Storage is in memory, so restarting the pod throws away every trace. Use
`backends/tempo-grafana/` if you want to keep anything.

Remove it with `kubectl delete namespace tracing`.
