# Feb 4 2026 - Setting HPA using K8s

## 1.	create a cluster

Run command:

```bash
kind create cluster --config cluster_config/cluster.k8s.yaml --wait 5m
```

Delete the cluster:

```bash
kind delete cluster --name cluster
```

## 2.	deploying pods and expose service

Before deploying, see if you're in the right cluster. If not, switch to the correct cluster using command:

```bash
kubectl config get-contexts
kubectl config use-context kind-cluster
```

running command to deploy pods: 

```bash
kubectl apply -f ./deploy_config/deploy.k8s.yaml
```

check by running : 
```bash
kubectl get pods
```


Run this command to expose the service:

```bash
kubectl apply -f ./deploy_config/service.k8s.yaml
```

After completion, visit: [http://localhost/](http://localhost/) , you can see nginx service running.

You can also check via running the following command to see more details:

```bash
kubectl get services
```

## 3.	Install Metrics Server

Install Metrics Server(every time you create a new cluster):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

or :

```bash
kubectl apply -f ./metricsServer_config/metrics_service.yaml
```

when finished run this command:

```bash
kubectl -n kube-system rollout status deploy/metrics-server
```

For my case, I need a little fix. Open up a new terminal window and run :

```bash
kubectl -n kube-system patch deployment metrics-server --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"}
]'
kubectl -n kube-system rollout restart deploy/metrics-server
kubectl -n kube-system rollout status deploy/metrics-server
```

check to see if successfully installed:

```bash
kubectl top nodes
kubectl top pods
```

## 4.	Testing Metrics Server

Generate CPU load using the following command, and let it run:

```bash
kubectl run -it --rm loadgen --restart=Never --image=busybox:1.28 -- \
  sh -c 'while true; do wget -q -O- http://example1 >/dev/null; echo -n .; done'
```

Then open another terminal:

By running the following command, you can get a quick view of the CPU usage:

```bash
watch -n 2 "kubectl top pod -l app=example1 --containers"
```

Or running the following command to get a more continues view and store the data into  a file:

```bash
for i in $(seq 1 60); do
  date -u +"%Y-%m-%dT%H:%M:%SZ"
  kubectl top pod -l app=example1  --containers --no-headers
  echo "---"
  sleep 5
done | tee nginx-metrics-samples.txt
```

## 5.	Testing HPA

Running command to set up HPA:

```bash
kubectl apply -f ./hpa_config/hpa.k8s.yaml
```

check if succeeded:

```bash
kubectl get hpa example1-hpa
kubectl describe hpa example1-hpa
```

With same technique used above, running the following command to generate requests:

```bash
kubectl run -it --rm loadgen --restart=Never --image=busybox:1.28 -- \
  sh -c 'while true; do wget -q -O- http://example1 >/dev/null; done'
```

In another terminal, monitor the change by running:

```bash
kubectl get hpa example1-hpa --watch
```

With more load:

```bash
kubectl run -it --rm fortio --image=fortio/fortio --restart=Never -- \
  load -t 300s -c 10 -qps 2000 -loglevel Error http://example1
```

-c 10 = 10 workers/connections
-qps 2000 = Fortio tries to send 2000 HTTP requests per second overall (not per connection)


[⬅ Back to README](README.md)