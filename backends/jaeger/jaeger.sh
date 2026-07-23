# Esta cosa solo instala Jaeger para ponerlo como destino en Odigos

kubectl apply -f https://raw.githubusercontent.com/odigos-io/simple-demo/main/kubernetes/jaeger.yaml
kubectl wait --for=condition=available --timeout=300s deployment --all --all-namespaces

echo "\n############################################"
echo ""
echo "Esta ventana se va a quedar cargando, se va a hacer un port forward a jaeger"
echo ""
echo 'En Odigos, dentro de "Jaeger OTLP gRPC Endpoint" pones "jaeger.tracing:4317"'
kubectl port-forward -n tracing svc/jaeger 16686:16686
