# eBPF tracing POC

A two service Java application on Kubernetes, used as a fixed workload for comparing eBPF
auto instrumentation agents. The application is never modified: no SDK, no agent JAR, no code
changes. Every trace in this repository is produced by an agent reading the processes from
outside, which is the point of the exercise.

Three agents are wired up against the same workload:

| Agent | Directory | Image | Trace destination as configured |
|---|---|---|---|
| Grafana Beyla | `instrumentation/beyla/` | `grafana/beyla:latest` | in cluster Jaeger, `jaeger.tracing:4317` |
| OpenTelemetry eBPF Instrumentation (OBI) | `instrumentation/obi/` | `otel/ebpf-instrument:v0.9.0` | Tempo on the host, `host.minikube.internal:4317` |
| Odigos | `instrumentation/odigos/` | installed by the Odigos CLI | chosen in the Odigos UI |

## Layout

```
apps/                 Java sources and Dockerfiles for both services
k8s/                  Namespace, Postgres, both services, ingress, plus deploy/test/traffic scripts
instrumentation/      One directory per eBPF agent
backends/             Trace destinations: Tempo and Grafana, Jaeger, ClickStack
minikube.sh           Creates and destroys the local cluster
```

## The workload

```
client -> java8-gateway (Spring Boot 2.7, Java 8) -> java17-service (Spring Boot 3.2, Java 17) -> PostgreSQL
```

The version split is deliberate. Java 8 and Java 17 have different JVM internals, so an agent that
handles one does not automatically handle the other, and the gap shows up quickly in the traces.

Both services inject random failures at roughly a 10 to 15 percent rate. That is also deliberate:
it gives the agents error spans to attribute without needing a separate fault injection tool.

Images are published at https://hub.docker.com/u/m0r4a, so the cluster does not need to build
anything to get started.

## Getting started

```bash
./minikube.sh create      # 10 CPUs, 12 GB, k8s v1.28.2, and mounts /sys/fs/bpf
cd k8s && ./deploy.sh     # namespace, Postgres, then both services in dependency order
./test.sh                 # one request per endpoint
```

`minikube.sh create` mounts the BPF filesystem inside the node. Beyla mounts `/sys/fs/bpf` with
`type: Directory`, so its DaemonSet will not schedule if that mount is missing.

Then pick an agent from `instrumentation/` and a destination from `backends/`, and follow the
README in each. To generate sustained load while you watch traces arrive:

```bash
cd k8s && ./traffic.sh --time 5     # minutes
```

Tear down with `./deploy.sh rm` for the application, or `./minikube.sh destroy` for the whole
cluster.

`deploy.sh`, `test.sh`, and `traffic.sh` resolve paths relative to the working directory, so run
them from inside `k8s/`.
