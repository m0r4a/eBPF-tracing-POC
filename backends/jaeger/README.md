# Jaeger

An in cluster Jaeger, applied straight from the Odigos demo repository. It is the fastest
destination to stand up, which is why both the Beyla and Odigos paths default to it.

```bash
./jaeger.sh
```

The script applies the manifest, waits for every deployment in the cluster to become available,
and then holds the terminal open port forwarding the UI to http://localhost:16686. It does not
return, so run it in its own terminal.

Jaeger lands in the `tracing` namespace. Its OTLP gRPC endpoint is `jaeger.tracing:4317`, which is
what you enter in the Odigos UI and what `instrumentation/beyla/beyla-config.yaml` already points
at.

Note that `kubectl wait ... --all --all-namespaces` waits on every deployment in the cluster, not
just Jaeger. If anything else is unhealthy the script will sit there for the full 300 seconds
before timing out.

Storage is in memory. Restarting the pod discards every trace. For anything you want to keep, use
`backends/tempo-grafana/` instead.
