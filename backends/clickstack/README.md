# ClickStack

ClickStack is ClickHouse's observability stack: a ClickHouse backend, an OpenTelemetry collector, and
the HyperDX UI. I used it as an Odigos destination mainly to get logs and traces correlated in one
place instead of only traces.

The earlier version of this POC carried a full copy of the upstream repository, unmodified, around
1 MB of committed images and vendor files. There is nothing local worth keeping, so clone it instead:

```bash
git clone https://github.com/ClickHouse/ClickStack.git .
docker compose up -d
```

Run that from inside this directory. Everything except this README is gitignored, so the clone will
not end up in the repo.

If you need to reproduce exactly what the original POC ran, the reference is commit `421369b`
("feat: copy over compose file from oss repo").

Ports, credentials, and the OTLP endpoint to give Odigos are all in the upstream README. Those are
upstream's to change, so there is no point mirroring them here.

Unlike the other two backends, I have not re-tested this one recently, so treat the upstream docs as
the source of truth rather than anything here.
