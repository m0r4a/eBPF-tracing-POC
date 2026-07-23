# Kubernetes manifests

Puts the Java 8 gateway, the Java 17 service, and PostgreSQL into the `ebpf-poc` namespace.

```
client -> java8-gateway -> java17-service -> PostgreSQL
```

Run the scripts from inside this directory. Their paths are relative and I never made them work from
anywhere else.

## Deploying

```bash
./deploy.sh
```

That applies everything in order and waits at each step. By hand, if you want to watch it or only
apply part of it:

```bash
kubectl apply -f namespace/
kubectl apply -f database/
kubectl wait --for=condition=ready pod -l app=postgres -n ebpf-poc --timeout=120s
kubectl apply -f java17-service/
kubectl wait --for=condition=ready pod -l app=java17-service -n ebpf-poc --timeout=120s
kubectl apply -f java8-gateway/
kubectl apply -f ingress/          # optional, see below
```

`deploy.sh` also does status and logs:

```bash
./deploy.sh status
./deploy.sh logs gateway     # or service, database, all
./deploy.sh rm               # asks before deleting the namespace
```

`./deploy.sh logs` with no component filters both application logs down to transaction lines.

## Seed the database

Do this once after deploying and before sending traffic.

Hibernate creates the tables but they come up empty. The application ships
`apps/app_java_17/src/main/resources/data.sql` with three users and four orders, and Spring Boot
never runs it, because `spring.sql.init.mode` defaults to `embedded` and PostgreSQL is not embedded.
Nothing is broken, the tables are just empty, and every read returns `User not found` or `"count":0`
until you load it yourself:

```bash
kubectl exec -i -n ebpf-poc deploy/postgres -- psql -U postgres -d appdb \
  < ../apps/app_java_17/src/main/resources/data.sql
```

Load it on a fresh database before any `POST /api/users`. The seeded orders reference user IDs 1 to
3, and IDs come from a sequence, so a user you created earlier takes ID 1 and the orders end up
attached to the wrong people.

Check it worked:

```bash
kubectl exec -n ebpf-poc deploy/postgres -- psql -U postgres -d appdb \
  -c "select count(*) from users;"    # should be 3
```

Nothing creates orders through the API, so this is the only way to get rows back from
`/api/orders/{id}`. Skip it and the database hop still shows up in traces, just always empty.
`apps/README.md` explains why and how to fix it in the image.

## Getting to the gateway

`java8-gateway` is a `LoadBalancer` Service on port 80. Under minikube it also gets a NodePort in
the 30000 to 32767 range, which is what `minikube service` gives you:

```bash
export GATEWAY_URL=$(minikube service java8-gateway -n ebpf-poc --url)
echo $GATEWAY_URL      # something like http://192.168.49.2:30547
```

If you want a real external IP on port 80, run `sudo minikube tunnel` in another terminal and read
the address from `kubectl get svc java8-gateway -n ebpf-poc`. On Windows there is no sudo: run
`minikube tunnel` from an elevated terminal instead. The NodePort route above needs no elevation.

On a kubeadm cluster with no load balancer the external IP stays `<pending>`, so use the NodePort
from the same output with any node IP from `kubectl get nodes -o wide`:

```bash
export GATEWAY_URL="http://<node-ip>:30547"
```

`test.sh` and `traffic.sh` both call `minikube service`, so they only work on minikube. Anywhere else
use the curl commands below with `GATEWAY_URL` set yourself.

### Ingress

`ingress/` is optional and needs more setup than the NodePort route, which is why nothing depends on
it. It routes `ebpf-poc.local` to the gateway and needs the nginx controller:

```bash
minikube addons enable ingress
kubectl apply -f ingress/
echo "$(minikube ip) ebpf-poc.local" | sudo tee -a /etc/hosts
curl http://ebpf-poc.local/api/health
```

## Testing

```bash
./test.sh
```

One request per endpoint, then 10 more to show the error injection, then the last transaction lines
from both services.

One thing to know: `test.sh` always posts `test@example.com` and the email column is unique, so the
create-user step works the first time and returns a 500 constraint violation on every run after that
against the same database. Expected, and it does not affect the rest.

By hand, with `$GATEWAY_URL` set:

```bash
curl $GATEWAY_URL/api/health
# {"service":"java8-gateway","status":"UP"}

curl -X POST $GATEWAY_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Smith","email":"alice@example.com"}'

curl $GATEWAY_URL/api/users/1     # John Doe, if you seeded
curl $GATEWAY_URL/api/orders/1    # his two orders
```

Responses carry `"backend":"java17"` and `"gateway":"java8"` so you can tell the request actually
crossed both services. `/api/health` is the exception, the gateway answers it locally, so it makes a
single hop trace with no database span.

For continuous traffic while you watch traces arrive:

```bash
./traffic.sh --time 5      # minutes, defaults to 1
```

It picks randomly from the six endpoints and sleeps 100 to 600 ms between requests. Emails are
random, so unlike `test.sh` you can run it as many times as you want.

### Errors

Both services fail on a percentage of requests, so you do not need a fault injection tool. Rates run
from 10 percent on the gateway to 15 percent on `GET /api/users/{id}` and stack across the two hops.
Full table is in `apps/README.md`.

```bash
for i in {1..20}; do
  curl -s $GATEWAY_URL/api/users/1 | jq -r '.error // "OK"'
  sleep 0.5
done
```

You get a mix of `OK`, `Simulated random error in gateway`, and `Simulated database connection
error`.

## Checking on things

```bash
kubectl get all -n ebpf-poc
kubectl logs -f -l app=java8-gateway -n ebpf-poc
kubectl logs -f -l app=java17-service -n ebpf-poc
kubectl logs -f -l app=postgres -n ebpf-poc
```

## Cleaning up

```bash
./deploy.sh rm
```

Or `kubectl delete namespace ebpf-poc`, or one directory at a time in reverse order
(`java8-gateway/`, `java17-service/`, `database/`, `namespace/`).

Deleting the namespace deletes the PVC too, so the seed data goes with it. Seed again after
redeploying.

## Resources

| Component | Replicas | Memory | CPU | Storage |
|---|---|---|---|---|
| Java 8 gateway | 2 | 384Mi to 768Mi | 200m to 400m | |
| Java 17 service | 2 | 512Mi to 1Gi | 250m to 500m | |
| PostgreSQL | 1 | 256Mi to 512Mi | 250m to 500m | 1Gi |

Both services run 2 replicas, so consecutive requests do not necessarily hit the same JVM. Worth
remembering when a trace looks like it came from the wrong process.

## Notes

PostgreSQL is on 18-alpine. Version 18 of the image changed where it keeps its data, so the volume
mounts at `/var/lib/postgresql` and Postgres puts the data in a version subdirectory under it. The
old `/var/lib/postgresql/data` mount makes the 18 image refuse to start, so do not change it back.

Health checks wait 30 to 60 seconds before the first probe to give the JVM time to boot. Shorten
that and pods will restart loop on a cold cluster.

Application logs use `Date|StartTime|EndTime|Latency|Endpoint|StatusCode`, which is what
`./deploy.sh logs` greps for.

Storage uses `storageClassName: standard`, the minikube default. You will need to change it
elsewhere.

Both deployments pin image tag `1.0.1` with `imagePullPolicy: Always`, so a locally built image
under that tag gets replaced by the registry copy. See `apps/README.md` if you are building.

Secrets are plain base64, which is not encryption. Fine for a throwaway cluster, not for anything
else.
