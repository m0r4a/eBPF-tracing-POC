# Tempo and Grafana

Runs on the host with Docker Compose, not in the cluster. Agents inside Minikube reach it through
`host.minikube.internal`.

```bash
docker compose up -d
```

| Service | Port | Notes |
|---|---|---|
| Grafana | 3000 | admin/admin, Tempo already provisioned as a datasource |
| Tempo | 3200 | UI and API |
| Tempo OTLP gRPC | 4317 | where the agents send spans |
| Tempo OTLP HTTP | 4318 | |

Zipkin (9411) and Jaeger ingest (14268) are present but commented out in `compose.yml`.

Images are Tempo 2.10.5 and Grafana 13.0.1. `traceqlEditor` is enabled, so you can write TraceQL
directly in the Grafana explore view instead of clicking through the search form.

## Files

- `compose.yml`
- `config/tempo.yaml`, mounted read only into the Tempo container
- `config/grafana/provisioning/datasources/tempo.yaml`, which is why Grafana needs no manual setup

Storage is local Docker volumes, `tempo-data-2` and `grafana-data`. `docker compose down -v`
discards both.

## Pointing an agent here

This is the default for OBI. For Beyla, change `otel_traces_export.endpoint` in
`instrumentation/beyla/beyla-config.yaml` from the Jaeger address to
`http://host.minikube.internal:4317`.

`host.minikube.internal` is a Minikube convenience and does not exist on a real cluster. There,
run Tempo in cluster and point the agents at its Service.

## If no traces arrive

Tempo's healthcheck is commented out in `compose.yml`, and so is Grafana's `depends_on`, so
Grafana will start whether or not Tempo is ready. An empty datasource usually means Tempo is
still starting rather than that the agent is broken. Check with
`curl http://localhost:3200/ready`.

The other common cause is sampling: both agents ship at `parentbased_traceidratio` 0.5, so half
of what you send never arrives by design.
