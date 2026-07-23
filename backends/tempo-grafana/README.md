# Tempo and Grafana

Runs on your machine with Docker Compose, not in the cluster. Agents inside minikube reach it through
`host.minikube.internal`.

```bash
docker compose up -d
```

Ports 3000, 3200, 4317, and 4318 have to be free. If you already run a Grafana on 3000 this will not
start, and the container names `tempo` and `grafana` are hardcoded, so it will also collide with any
other stack using those names. Change `container_name` and the port mappings in `compose.yml` if that
is your situation.

| Service | Port | Notes |
|---|---|---|
| Grafana | 3000 | admin/admin, Tempo already set up as a datasource |
| Tempo | 3200 | UI and API |
| Tempo OTLP gRPC | 4317 | where the agents send spans |
| Tempo OTLP HTTP | 4318 | |

Zipkin (9411) and Jaeger ingest (14268) are in `compose.yml` but commented out.

## Files

- `compose.yml`
- `config/tempo.yaml`, mounted read only into the Tempo container
- `config/grafana/provisioning/datasources/tempo.yaml`, which is why Grafana needs no manual setup

Data lives in local Docker volumes, `tempo-data-2` and `grafana-data`. `docker compose down -v`
throws both away.

## Versions

Tempo 3.0.2 and Grafana 13.1.1.

Tempo 3.0 reorganised its config and the old 2.x file will not load. If you have an older
`tempo.yaml` lying around, the parts that changed here were:

- `ingester:` is gone. Its job moved to the live-store, which needs no configuration in monolithic
  mode.
- `compactor:` is gone, replaced by a scheduler and worker pair. Block retention now lives under
  `backend_scheduler.provider.compaction.compaction`.
- `metrics_generator.traces_storage` is gone.

Everything else carried over unchanged. Tempo 3.0 does have a new Kafka based ingest path, but that
only applies in distributed mode, so a single container setup like this one still works with no extra
moving parts.

On the Grafana side, `GF_FEATURE_TOGGLES_ENABLE=traceqlEditor` was removed. That variable is
deprecated in Grafana 13 and the TraceQL editor has been on by default for a long time.

## Pointing an agent here

This is the default for OBI. For Beyla, change `otel_traces_export.endpoint` in
`instrumentation/beyla/beyla-config.yaml` from the Jaeger address to
`http://host.minikube.internal:4317`.

`host.minikube.internal` is a minikube convenience and does not exist on a real cluster. There you
would run Tempo in the cluster and point the agents at its Service.

## No traces showing up

Grafana starts whether or not Tempo is ready, so an empty datasource right after `docker compose up`
usually just means Tempo is still coming up. Check with `curl http://localhost:3200/ready`.

There is no healthcheck on Tempo to make Grafana wait, because the Tempo image is distroless and has
no shell or wget to run one with. That is also why `depends_on` is not set on Grafana.

Tempo also buffers before flushing, so the first traces of a run show up later than the requests that
produced them. Send a minute of load with `k8s/traffic.sh` instead of a single curl, and search a
wider time range than you think you need. The default search window is narrow enough that a trace
from two minutes ago can look missing when it is not.

The other usual suspect is sampling. Both agents ship at `parentbased_traceidratio` 0.5, so half of
what you send never arrives by design.
