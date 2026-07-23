# The application

Two Spring Boot services and a PostgreSQL database. None of it is instrumented: no OpenTelemetry
SDK, no agent JAR, no tracing code anywhere. That is the whole point. Every span you see comes from
an eBPF agent watching these processes from outside.

| Service | Directory | Runtime | Spring Boot | Image |
|---|---|---|---|---|
| java8-gateway | `app_java_8/` | Java 8 (`eclipse-temurin:8-jre-alpine`) | 2.7.18 | `m0r4a/java8-gateway:1.0.1` |
| java17-service | `app_java_17/` | Java 17 (`eclipse-temurin:17-jre-alpine`) | 3.2.0 | `m0r4a/java17-service:1.0.1` |

The gateway keeps no state, it just forwards to `java17-service`, which owns the JPA entities and
talks to PostgreSQL. The split across two Java versions is deliberate, since agents do not always
handle both equally well.

## Endpoints

Both services expose the same paths under `/api`, and the gateway forwards all of them except
health.

| Method | Path | Reaches java17 | Hits PostgreSQL |
|---|---|---|---|
| GET | `/api/health` | no | no |
| POST | `/api/users` | yes | yes |
| GET | `/api/users/{id}` | yes | yes |
| GET | `/api/orders/{userId}` | yes | yes |

The gateway answers `/api/health` by itself, so it makes a single hop trace with no database span.
If some of your traces look oddly short, that is usually why. `traffic.sh` includes health in its
rotation, so about a sixth of the load it generates is single hop.

Successful responses include `"gateway":"java8"` and `"backend":"java17"`, which is how you tell the
request really went through both services.

## Failures on purpose

Both services throw on a percentage of requests so there is something interesting in the traces.

| Where | Rate | Message |
|---|---|---|
| Gateway, any forwarded request | 10% | `Simulated random error in gateway` |
| java17, `GET /api/users/{id}` | 15% | `Simulated database connection error` |
| java17, `POST /api/users` | 10% | `Database write error` |
| java17, `GET /api/orders/{userId}` | 12% | `Query timeout` |

These stack, so a full request fails more often than any single row suggests.

## The seed data does not load by itself

`app_java_17/src/main/resources/data.sql` has three users and four orders in it, and Spring Boot
never runs it against PostgreSQL. It only runs `data.sql` when `spring.sql.init.mode` is `always`,
and the default is `embedded`. Hibernate still creates the tables through
`spring.jpa.hibernate.ddl-auto=update`, so you get empty tables rather than a crash.

What this looks like in practice: on a fresh database `GET /api/users/1` returns `User not found`
and `GET /api/orders/1` returns `"count":0`. The seeding step is in `k8s/README.md`.

There is no endpoint that creates orders, so posting users will never give you an order to look at.
Loading `data.sql` is the only way to get rows out of the database hop.

If you would rather fix it properly than work around it, add this to
`app_java_17/src/main/resources/application.properties` and rebuild:

```properties
spring.sql.init.mode=always
spring.jpa.defer-datasource-initialization=true
```

The second line matters, otherwise `data.sql` runs before Hibernate has created the tables.

## Other things worth knowing

`User.email` has a unique constraint, so posting the same email twice gives you a 500. `test.sh`
always posts `test@example.com`, which means its create-user step works the first time and fails
after that against the same database. `traffic.sh` randomises emails, so it does not have this
problem.

Both containers set `-Duser.timezone=America/Mexico_City`, so log timestamps are in that timezone no
matter where you run them.

## Building

You do not need to. The images are already on Docker Hub and the manifests point at them. Build only
if you change the code.

Both Dockerfiles are multi stage and run Maven inside the build, so no local JDK or Maven needed:

```bash
docker build -t m0r4a/java8-gateway:1.0.1 app_java_8/
docker build -t m0r4a/java17-service:1.0.1 app_java_17/
```

Watch out for the tag. Both deployments pin `1.0.1` with `imagePullPolicy: Always`, so a local build
under that tag gets replaced by the registry copy on the next pull. Either push it, or use a new tag
and update the deployment, or load it into the node and drop the pull policy:

```bash
minikube image load m0r4a/java8-gateway:1.0.1
```

## Running it without Kubernetes

Handy when you want to check the application itself with no agent involved:

```bash
docker network create ebpf-local

docker run -d --name postgres --network ebpf-local \
  -e POSTGRES_DB=appdb -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  postgres:18-alpine

docker run -d --name java17-service --network ebpf-local \
  -e DB_HOST=postgres -e DB_USER=postgres -e DB_PASSWORD=postgres -e DB_NAME=appdb \
  m0r4a/java17-service:1.0.1

docker run -d --name java8-gateway --network ebpf-local -p 8080:8080 \
  -e BACKEND_SERVICE_URL=http://java17-service:8080 \
  m0r4a/java8-gateway:1.0.1
```

Give the JVMs about 40 seconds, then seed and try it:

```bash
docker exec -i postgres psql -U postgres -d appdb < app_java_17/src/main/resources/data.sql
curl localhost:8080/api/orders/1
```

Clean up with `docker rm -f java8-gateway java17-service postgres && docker network rm ebpf-local`.

On first boot the java17 logs show two Hibernate warnings about a constraint that does not exist.
That is normal, it is just `ddl-auto=update` trying to drop something on an empty schema.

## Configuration

The gateway reads `BACKEND_SERVICE_URL` and defaults to `http://java17-service:8080`.

The service reads `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD`, defaulting to
`postgres:5432/appdb` as user `postgres`. In the cluster the first four come from the `java17-config`
ConfigMap and the password comes from the `postgres-secret` Secret.

Both write transaction lines as `Date|StartTime|EndTime|Latency|Endpoint|StatusCode`, which is what
`./deploy.sh logs` greps for.
