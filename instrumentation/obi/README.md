# OpenTelemetry eBPF Instrumentation (OBI)

Runs `otel/ebpf-instrument:v0.10.0` as a privileged DaemonSet with `hostPID: true` so it can see the
processes on the node. OBI is the upstream project Beyla was donated to, so the two configs look
similar on purpose and the differences are the interesting part.

## Files

- `rbac.yaml` gives the `obi` ServiceAccount read access to pod metadata, which is what puts
  Kubernetes names on the spans instead of bare PIDs.
- `obi-config.yaml` is the ConfigMap OBI reads from `/config/obi-config.yml`.
- `OBI.yaml` is the DaemonSet.

Only `rbac.yaml` sets a namespace, and it hardcodes `default`. So OBI ends up in `default` and
watches `ebpf-poc` from there through the ClusterRole. If your kubectl context points somewhere else
the ServiceAccount and the DaemonSet land in different namespaces and the pod will not start. Switch
to `default` before applying, or change both files together.

## Deploy

Start the backend on your machine first:

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

Grafana is at http://localhost:3000 with admin/admin and Tempo already set up as a datasource. Send
some traffic with `cd ../../k8s && ./traffic.sh --time 5` and search from the Explore view.

Give it a minute. Tempo buffers before flushing, so the first traces take longer to appear than the
requests that made them.

You will know OBI has attached when the logs say `instrumenting process` with `type=java`. Traffic
sent before that line does not get traced.

## Configuration

Traces go to `http://host.minikube.internal:4317`, meaning OBI inside the cluster reaches Tempo
running in Docker on your machine. That address only exists on minikube. On a real cluster you would
run Tempo in the cluster and point at its Service.

`OTEL_EBPF_AUTO_TARGET_EXE` is `*/java`. This matches the executable path, not the command line, and
the JVMs run as `/opt/java/openjdk/bin/java`. It used to be `*.jar` here, which looks reasonable and
never matches anything, so OBI was only finding the pods through the namespace rule in the config.
Discovery is also scoped to the `ebpf-poc` namespace with `kube-system` excluded.

Sampling is `parentbased_traceidratio` at 0.50, so half your traces are dropped on purpose. Set it to
`"1.0"` while debugging.

`OTEL_EBPF_LOG_LEVEL=DEBUG` and `OTEL_EBPF_BPF_DEBUG=true` are both on. The second one is very loud
and prints from inside the BPF programs, which helps when probes will not attach and is noise the
rest of the time.

`attributes.select.sql_client_duration` asks for all attributes on database spans instead of the
trimmed default set. Whether you actually get SQL spans depends on the agent picking up the JDBC
traffic, which I have seen work inconsistently, so do not assume the setting alone guarantees them.

`OTEL_EBPF_KUBE_CLUSTER_NAME` is `minikube-poc` and shows up as the cluster attribute on spans.

## Requirements

The DaemonSet mounts `/sys/fs/bpf` with `hostPath.type: DirectoryOrCreate`, which is more forgiving
than Beyla, which needs the directory to already exist. It also mounts `/sys/kernel/debug` with
`type: Directory`, which the minikube node image has.

`./minikube.sh create` mounts the BPF filesystem either way, but that mount does not survive a
`minikube stop`.
