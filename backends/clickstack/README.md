# ClickStack

ClickStack is ClickHouse's observability stack: a ClickHouse backend, an OpenTelemetry collector,
and the HyperDX UI. It was used in the MegaPOC as an Odigos destination, mainly to see logs and
traces correlated in one place rather than only traces.

The earlier POC carried a full checkout of the upstream repository, unmodified, at about 1 MB of
committed images and vendor files. There is nothing local to preserve, so clone it instead:

```bash
git clone https://github.com/ClickHouse/ClickStack.git .
docker compose up -d
```

Run that from inside this directory. Everything except this README is gitignored, so the clone
will not pollute the repository.

The reference point, if you need to reproduce what the original POC ran, is commit `421369b`
("feat: copy over compose file from oss repo").

Consult the upstream README for ports, credentials, and the OTLP endpoint to give Odigos. Those
are upstream's to change and are not worth mirroring here.
