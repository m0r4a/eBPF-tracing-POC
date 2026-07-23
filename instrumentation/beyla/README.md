# Grafana Beyla

Runs `grafana/beyla:3.29.0` as a privileged DaemonSet with `hostPID: true`, so it can see every
process on the node and attach to both JVMs without touching them.

Beyla 3.x is built on OBI internally, which you can see in its own logs. If you are comparing the two
agents here, that is worth knowing before you read too much into small differences.

## Files

- `rbac.yaml` gives the `beyla` ServiceAccount read access to pod metadata, which is what puts
  Kubernetes names on the spans instead of bare PIDs.
- `beyla-config.yaml` is the ConfigMap Beyla reads from `/config/beyla-config.yml`.
- `beyla.yaml` is the DaemonSet.

Only `rbac.yaml` sets a namespace, and it hardcodes `default`. So Beyla ends up in `default` and
watches `ebpf-poc` from there through the ClusterRole. If your kubectl context points somewhere else
the ServiceAccount and the DaemonSet land in different namespaces and the pod will not start. Switch
to `default` before applying, or change both files together.

## Deploy

Start a backend first. As shipped this points at Jaeger in the cluster:

```bash
../../backends/jaeger/jaeger.sh
```

That holds the terminal open doing a port forward, so give it its own. Then:

```bash
kubectl apply -f rbac.yaml
kubectl apply -f beyla-config.yaml
kubectl apply -f beyla.yaml
kubectl logs -f -l app=beyla
```

Send traffic with `cd ../../k8s && ./traffic.sh --time 5`, then look for `java8-gateway` and
`java17-service` at http://localhost:16686.

## Configuration

Traces go to `http://jaeger.tracing:4317` over gRPC. To send them to the Tempo and Grafana stack in
`backends/tempo-grafana/` instead, change `otel_traces_export.endpoint` in `beyla-config.yaml` to
`http://host.minikube.internal:4317`, which is how OBI reaches it.

Discovery is scoped to the `ebpf-poc` namespace with `kube-system` excluded. Sampling is
`parentbased_traceidratio` at 0.5, so half the traces are dropped. Set it to `"1.0"` while debugging,
because a dropped span and a missing span look identical from the UI.

`BEYLA_LOG_LEVEL` is `DEBUG` and `BEYLA_PRINT_TRACES` is on. Noisy, but it means you can tell whether
Beyla is producing spans even when the backend is misconfigured. If the logs show spans and Jaeger
does not, the endpoint is wrong.

`BEYLA_AUTO_TARGET_EXE` is commented out, so Beyla finds targets by namespace rather than by
executable. OBI does it the other way around. If you do turn it on, note the pattern matches the
executable path, so `*/java` works and `*.jar` does not.

`BEYLA_KUBE_CLUSTER_NAME` is `minikube-poc` and shows up as the cluster attribute on spans. It does
not have to match your minikube profile name.

## Requirements

The DaemonSet mounts two host paths, both `hostPath.type: Directory`, so both have to exist on the
node already:

- `/sys/fs/bpf`, mounted `Bidirectional`. `./minikube.sh create` sets this up, but it does not
  survive a `minikube stop`. Redo it with `minikube ssh -- "sudo mount -t bpf bpf /sys/fs/bpf"`.
- `/sys/kernel/debug`, which the minikube node image already has.

If either is missing the pod sits there pending on a mount error and says nothing about eBPF, so
check this first when the DaemonSet never comes up. OBI is more relaxed here and uses
`DirectoryOrCreate` for `/sys/fs/bpf`.
