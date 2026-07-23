# eBPF tracing POC

Three eBPF auto instrumentation agents pointed at the same Java application, so you can compare
what each one gives you without changing a line of application code.

## Why this exists

I keep trying to push observability forward at work, and I keep running into the same wall. The
tooling is not usually the problem. Getting teams to instrument their applications is. Adding an
SDK means touching code that already works, going through review, and owning a new dependency, and
most teams have better things to do that quarter. So the traces never show up and the conversation
stops there.

eBPF agents are one way around that, since they read the running processes from outside instead of
asking anyone to import a library. I built a proof of concept for a few of them and showed my boss
the options side by side, which is a much easier conversation than "please instrument your service".

These are those POCs, cleaned up and published as a personal project. Nothing here is company code.
The application is a throwaway I wrote to have something realistic to trace.

## What is here

| Agent | Directory | Image | Where traces go by default |
|---|---|---|---|
| Grafana Beyla | `instrumentation/beyla/` | `grafana/beyla:3.29.0` | Jaeger in the cluster |
| OpenTelemetry eBPF Instrumentation (OBI) | `instrumentation/obi/` | `otel/ebpf-instrument:v0.10.0` | Tempo on your machine |
| Odigos | `instrumentation/odigos/` | installed by its own CLI | whatever you pick in its UI |

```
apps/                 Java sources and Dockerfiles for both services
k8s/                  Namespace, Postgres, both services, ingress, and the deploy/test/traffic scripts
instrumentation/      One directory per agent
backends/             Places to send traces: Tempo and Grafana, Jaeger, ClickStack
minikube.sh           Creates and destroys the local cluster
.justfile             One command per agent and backend combination
```

Every directory has its own README. Start here, then read the one for whichever agent you want.

## The application

```
client -> java8-gateway (Spring Boot 2.7, Java 8) -> java17-service (Spring Boot 3.2, Java 17) -> PostgreSQL
```

The two different Java versions are on purpose. Java 8 and Java 17 have different JVM internals, so
an agent that works on one does not automatically work on the other, and you find that out fast.

Both services also fail on purpose, somewhere between 10 and 15 percent of requests depending on the
endpoint, so there are error spans to look at without setting up a fault injection tool. Exact rates
are in `apps/README.md`.

The images are on Docker Hub at https://hub.docker.com/u/m0r4a, so you do not have to build
anything.

## What you need

minikube, kubectl, docker, and curl. jq is optional and only makes `test.sh` output nicer. Odigos
also needs its own CLI, which is not committed here. `just compat` checks all of this for you.

The cluster asks for 10 CPUs and 12 GB of RAM. If your machine cannot spare that, override them
rather than editing the script:

```bash
CPUS=4 MEMORY=6144 ./minikube.sh create
```

The agents need a node kernel with BTF and uprobes, which the default minikube node image has.

## Windows and Linux

This works on both, and unlike some eBPF tooling there is no hard Windows blocker, because none of
the privileged work happens on your machine. The agents run as DaemonSets inside the minikube node,
which is Linux no matter what you are sitting in front of. Even the BPF mount step is
`minikube ssh -- sudo mount ...`, where the sudo belongs to the node.

| | Linux, macOS | Windows via WSL2 | Windows via Git Bash |
|---|---|---|---|
| Cluster and application | yes | yes | yes |
| Beyla, OBI, Odigos | yes | yes | yes |
| Scripts and `just` | yes | yes | yes |
| PowerShell alone | n/a | n/a | no |

The scripts and the justfile use bash, `sed` and `docker compose`, so on Windows run them from WSL2
or Git Bash. PowerShell on its own is not enough. That is a shell requirement, not an eBPF one.

On the kernel question, which is the one that usually bites: Docker Desktop on Windows runs
containers on the WSL2 kernel, and every current WSL2 kernel branch is built with
`CONFIG_DEBUG_INFO_BTF`, `CONFIG_UPROBES`, `CONFIG_BPF_SYSCALL` and `CONFIG_DEBUG_FS`. Those are
what Beyla and OBI need in order to attach.

A few practical differences:

The 10 CPUs and 12 GB come out of the Docker Desktop VM on Windows and macOS, so raise its limits
first (`.wslconfig` on Windows) or minikube will refuse to start.

`sudo minikube tunnel`, mentioned under `k8s/` as an alternative way to reach the gateway, has no
sudo on Windows. Run `minikube tunnel` from an elevated terminal instead. The NodePort route that
everything else uses needs no elevation at all.

`.gitattributes` pins scripts, YAML, `data.sql` and the justfile to LF. Git for Windows defaults to
`core.autocrlf=true`, and a script checked out with CRLF fails as `bad interpreter: /bin/bash^M`,
naming the interpreter rather than the real problem. The same corruption would break `data.sql`
being piped into psql. If you cloned before that file existed,
`git rm --cached -r . && git reset --hard` re-normalises your working copy.

One thing I have not verified: whether `/sys/kernel/debug` is present inside the node under Docker
Desktop specifically. Beyla mounts it with `type: Directory` and will not schedule without it. If
its DaemonSet stays pending on Windows, that is the first thing to check.

## Getting started

If you have [just](https://github.com/casey/just), one command gets you a whole variation from
nothing: cluster, application, seed data, backend and agent.

```bash
just compat           # check your platform and tooling first
just obi-tempo        # or beyla-jaeger, beyla-tempo, obi-jaeger, odigos
just traffic 5        # generate load while you watch traces arrive
```

`just` on its own lists everything. Running a variation twice is harmless, and switching between
them removes the previous agent first. The rest of this section is the same thing by hand.

```bash
./minikube.sh create      # 10 CPUs, 12 GB, k8s v1.35.1, and mounts /sys/fs/bpf
cd k8s && ./deploy.sh     # namespace, Postgres, then both services in order
```

Then load the seed data. The application ships a `data.sql` that Spring Boot does not actually run
against PostgreSQL, so without this step the tables are empty and every read comes back
`User not found`:

```bash
kubectl exec -i -n ebpf-poc deploy/postgres -- psql -U postgres -d appdb \
  < ../apps/app_java_17/src/main/resources/data.sql
```

Do it before sending traffic, because the seeded orders point at user IDs 1 to 3. Then check it
works:

```bash
./test.sh
```

Now pick an agent from `instrumentation/` and a backend from `backends/` and follow those READMEs.
Beyla and Odigos default to Jaeger, which is the fastest to get running. OBI defaults to Tempo and
Grafana.

To generate traffic while you watch traces come in:

```bash
cd k8s && ./traffic.sh --time 5     # minutes
```

Clean up with `./deploy.sh rm` for the application, or `./minikube.sh destroy` for everything.

`deploy.sh`, `test.sh`, and `traffic.sh` use relative paths, so run them from inside `k8s/`.

## About the BPF mount

`minikube.sh create` mounts the BPF filesystem inside the node. Beyla mounts `/sys/fs/bpf` with
`type: Directory`, so its DaemonSet will not start if that mount is not there.

The mount does not survive `minikube stop`, and `minikube.sh` only has create and destroy, so after
restarting a stopped cluster do it yourself:

```bash
minikube ssh -- "sudo mount -t bpf bpf /sys/fs/bpf"
```

## Nothing is showing up in the backend

Go in this order, because each step rules out the next one.

Check the application first. Run `./test.sh` and confirm you get 200s with `"backend":"java17"` in
the response. There is no trace for a request that never happened.

Check the agent is running. Beyla and OBI deploy into whatever namespace your kubectl context is
pointing at, which is `default` unless you changed it. If `kubectl get pods -l app=beyla` shows
nothing, the DaemonSet never scheduled, and it is usually the `/sys/fs/bpf` mount.

Check the agent is producing spans. Both ship with debug logging on, so `kubectl logs -l app=beyla`
shows spans as they are built. If you see spans there but nothing in the UI, the problem is the
export endpoint, not the instrumentation.

Remember half of them are dropped on purpose. Both agents sample at
`parentbased_traceidratio` 0.5. Set it to `"1.0"` while you are debugging, because a dropped span
and a missing span look exactly the same from the UI.

## Versions

Everything was updated and tested in July 2026. The application images are pinned at 1.0.1 and are
the only thing I built.

| Component | Version |
|---|---|
| Kubernetes (minikube) | v1.35.1 |
| PostgreSQL | 18-alpine |
| Beyla | 3.29.0 |
| OBI | v0.10.0 |
| Tempo | 3.0.2 |
| Grafana | 13.1.1 |

Tempo 3.0 changed its config format, and PostgreSQL 18 changed where the image keeps its data. Both
configs in this repo are updated for that. If you pin older images, expect them not to match.
