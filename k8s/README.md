# Kubernetes manifests

Deploys the Java 8 gateway, the Java 17 service, and PostgreSQL into the `ebpf-poc` namespace.

```
client -> java8-gateway -> java17-service -> PostgreSQL
```

Run all scripts from inside this directory. Their paths are relative and were never adjusted for
any other working directory.

## Deploying

```bash
./deploy.sh
```

That applies everything in dependency order and waits at each step. The manual equivalent, if you
want to watch it happen or apply only part of it:

```bash
kubectl apply -f namespace/
kubectl apply -f database/
kubectl wait --for=condition=ready pod -l app=postgres -n ebpf-poc --timeout=120s
kubectl apply -f java17-service/
kubectl wait --for=condition=ready pod -l app=java17-service -n ebpf-poc --timeout=120s
kubectl apply -f java8-gateway/
kubectl apply -f ingress/          # optional
```

`deploy.sh` also takes `status` and `logs`:

```bash
./deploy.sh status
./deploy.sh logs gateway     # or service, database, all
./deploy.sh rm               # prompts before deleting the namespace
```

`./deploy.sh logs` with no component filters both application logs down to transaction lines only.

## Reaching the gateway

Under Minikube:

```bash
export GATEWAY_URL=$(minikube service java8-gateway -n ebpf-poc --url)
echo $GATEWAY_URL      # for example http://192.168.49.2:30547
```

That URL combines the Minikube node IP with the NodePort assigned from the 30000 to 32767 range.

If you would rather use a real LoadBalancer, run `sudo minikube tunnel` in a separate terminal,
then read the external IP from `kubectl get svc java8-gateway -n ebpf-poc` and use port 80
directly.

On a kubeadm cluster, take the NodePort from the same `kubectl get svc` output and combine it with
any node IP from `kubectl get nodes -o wide`:

```bash
export GATEWAY_URL="http://<node-ip>:30547"
```

## Testing

```bash
./test.sh
```

That runs one request against each endpoint. To do it by hand, with `$GATEWAY_URL` set:

```bash
curl $GATEWAY_URL/api/health
# {"status":"UP","service":"java8-gateway"}

curl -X POST $GATEWAY_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Smith","email":"alice@example.com"}'

curl $GATEWAY_URL/api/users/1     # user 1 is preloaded
curl $GATEWAY_URL/api/orders/1    # its two orders
```

Successful responses carry `"backend":"java17"` and `"gateway":"java8"`, so you can confirm the
request actually crossed both services rather than being answered at the edge.

For sustained load while watching traces arrive:

```bash
./traffic.sh --time 5      # minutes, defaults to 1
```

### Errors

Both services inject random failures at roughly 10 to 15 percent, so you do not need a fault
injection tool to get error spans. Just send enough requests:

```bash
for i in {1..20}; do
  curl -s $GATEWAY_URL/api/users/1 | jq -r '.error // "OK"'
  sleep 0.5
done
```

You will see a mix of `OK`, `Simulated random error in gateway`, and
`Simulated database connection error`.

## Verifying

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

Or by hand, with `kubectl delete namespace ebpf-poc`, or one directory at a time in reverse order
(`java8-gateway/`, `java17-service/`, `database/`, `namespace/`).

## Resources

| Component | Replicas | Memory | Storage |
|---|---|---|---|
| Java 8 gateway | 2 | 384Mi to 768Mi | |
| Java 17 service | 2 | 512Mi to 1Gi | |
| PostgreSQL | 1 | 256Mi to 512Mi | 1Gi |

## Notes

Health checks allow 30 to 60 seconds before the first probe, to give the JVM time to start. Cutting
that down will make pods restart loop on a cold cluster.

Application logs follow the format `Date|StartTime|EndTime|Latency|Endpoint|StatusCode`, which is
what `./deploy.sh logs` filters on.

Storage uses `storageClassName: standard`, which is the Minikube default and may need changing
elsewhere.

Secret values are plain base64, which is not encryption. Acceptable for a throwaway POC cluster
and nowhere else.
