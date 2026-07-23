# OpenTelemetry eBPF Instrumentation (OBI)

Runs `otel/ebpf-instrument:v0.9.0` as a privileged DaemonSet with `hostPID: true`. OBI is the
upstream project Beyla was donated to, so the two configs look similar on purpose and the
differences below are the interesting part.

## Files

- `rbac.yaml` gives the `obi` ServiceAccount read access to pod metadata for Kubernetes decoration.
- `obi-config.yaml` is the ConfigMap OBI reads from `/config/obi-config.yml`.
- `OBI.yaml` is the DaemonSet.

## Deploy

Start the trace destination on the host first:

```bash
cd ../../backends/tempo-grafana && docker compose up -d
```

Then:

```bash
kubectl apply -f rbac.yaml
kubectl apply -f obi-config.yaml
kubectl apply -f OBI.yaml
kubectl logs -f -l app=obi
```

Grafana comes up at http://localhost:3000 with admin/admin and Tempo already provisioned as a
datasource.

## Configuration

Traces go to `http://host.minikube.internal:4317`, meaning OBI inside the cluster reaches Tempo
running in Docker on the host. That address only resolves under Minikube. On a real cluster,
point it at a Tempo Service instead.

`OTEL_EBPF_AUTO_TARGET_EXE` is `*.jar`, so OBI selects targets by executable name. Discovery is
additionally scoped to the `ebpf-poc` namespace with `kube-system` excluded. Sampling is
`parentbased_traceidratio` at 0.50.

Both `OTEL_EBPF_LOG_LEVEL=DEBUG` and `OTEL_EBPF_BPF_DEBUG=true` are on. The second one is loud
and prints from inside the BPF programs themselves, which is useful when probes are failing to
attach and useless otherwise.

`attributes.select.sql_client_duration` includes all attributes, so database spans carry the full
query metadata rather than the default trimmed set. That is what makes the PostgreSQL hop
readable in the trace view.

## Requirements

The DaemonSet mounts `/sys/fs/bpf` with `hostPath.type: DirectoryOrCreate`, so it is more
forgiving than the Beyla setup, which requires the directory to exist. `./minikube.sh create` at
the repo root mounts it either way.
