# update k8s config
aws eks update-kubeconfig --name k8s --region eu-west-1

# Install istio
kubectl apply -f 1-istio-init.yaml
kubectl apply -f 2-istio-minikube.yaml
kubectl apply -f 3-kiali-secret.yaml

# Label namespace to enalbe sidecar on any pod
kubectl label namespace default istio-injection=enabled

# Install fleet-man app
kubectl apply -f 4-application-full-stack.yaml


# WebApp
kubectl port-forward svc/fleetman-webapp 30080:80

# Kiali-web
kubectl port-forward -n istio-system svc/kiali 31000:20001
# Kiali metrics
kubectl port-forward -n istio-system svc/kiali 30148:9090
# Jaeger-web
kubectl port-forward -n istio-system svc/tracing 30101:80


kubectl rollout restart deployment istiod -n istio-system

# Test DNS resolution from a pod
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -- /bin/bash
# Once inside the pod:
nslookup istiod.istio-system.svc.cluster.local

kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl logs -n kube-system -l k8s-app=aws-node
