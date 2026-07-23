# Grafana Beyla

Runs `grafana/beyla:latest` as a privileged DaemonSet with `hostPID: true`, so it can see every
process on the node and attach to the two JVMs without touching them.

## Files

- `rbac.yaml` gives the `beyla` ServiceAccount read access to pod metadata, which is what makes
  spans come out labelled with Kubernetes names instead of bare PIDs.
- `beyla-config.yaml` is the ConfigMap Beyla reads from `/config/beyla-config.yml`.
- `beyla.yaml` is the DaemonSet.

## Deploy

Bring up a destination first. As shipped the config points at in cluster Jaeger:

```bash
../../backends/jaeger/jaeger.sh
```

Then:

```bash
kubectl apply -f rbac.yaml
kubectl apply -f beyla-config.yaml
kubectl apply -f beyla.yaml
kubectl logs -f -l app=beyla
```

## Configuration

Traces go to `http://jaeger.tracing:4317` over gRPC. To send them to the Tempo and Grafana stack
in `backends/tempo-grafana/` instead, change `otel_traces_export.endpoint` in `beyla-config.yaml`
to `http://host.minikube.internal:4317`, which is how the OBI setup reaches it.

Discovery is scoped to the `ebpf-poc` namespace and explicitly excludes `kube-system`. Sampling is
`parentbased_traceidratio` at 0.5, so half the traces are dropped. Raise `arg` to `"1.0"` while
debugging, since a missing span and a sampled out span look identical from the UI.

`BEYLA_LOG_LEVEL` is `DEBUG` and `BEYLA_PRINT_TRACES` is on, which makes the DaemonSet logs verbose
but means you can confirm Beyla is producing spans even when the destination is misconfigured.

`BEYLA_AUTO_TARGET_EXE` is commented out, so Beyla discovers targets by namespace rather than by
executable name. The OBI setup takes the opposite approach and matches `*.jar`.

## Requirements

The DaemonSet mounts `/sys/fs/bpf` with `hostPath.type: Directory`, so the path must already exist
on the node. `./minikube.sh create` at the repo root handles this. Without it the pod stays
pending on a mount error rather than reporting anything about eBPF.
