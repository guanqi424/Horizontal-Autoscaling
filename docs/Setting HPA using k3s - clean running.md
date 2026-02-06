# Feb 4 2026 - Setting HPA using K3s

##### Usage

Check out what you can do via `k3d help` or check the docs @ [k3d.io](https://k3d.io)

Example Workflow: Create a new cluster and use it with `kubectl`

1. `k3d cluster create CLUSTER_NAME` to create a new single-node cluster (= 1 container running k3s + 1 loadbalancer container)
2. [Optional, included in cluster create] `k3d kubeconfig merge CLUSTER_NAME --kubeconfig-switch-context` to update your default kubeconfig and switch the current-context to the new one
3. execute some commands like `kubectl get pods --all-namespaces`
4. `k3d cluster delete CLUSTER_NAME` to delete the default cluster

## 1.create cluster

Run command:

```bash
k3d cluster create --config ./cluster_config/cluster.k3s.yaml
```

Use the following command to check if created successfully:

```bash
k3d cluster list
```

Delete it using:
```bash
k3d cluster delete k3sTest
``` 

## 2.deploying pods

Before deploying, see if you're in the right cluster. If not, switch to the correct cluster using command:

```bash
kubectl config get-contexts
kubectl config use-context k3d-k3sTest
```

running command to deploy pods: 

```bash
kubectl apply -f ./deploy_config/deploy.k3s.yaml
```
check by running : 

```bash
kubectl get pods
```

Run this command to expose service:

```bash
kubectl apply -f ./deploy_config/service.k3s.yaml
```

After completion, visit: [http://localhost:81](http://localhost:81) , you can see nginx service running.

You can also check via running the following command to see more details:

```bash
kubectl get services
```

## 4.Metrics Server

check to see if it's successfully deployed:

```bash
kubectl top nodes
kubectl top pods
```

Generate CPU load using the following command, and let it run:

```bash
kubectl run -it --rm loadgen --restart=Never --image=busybox:1.28 -- \
  sh -c 'while true; do wget -q -O- http://example2 >/dev/null; echo -n .; done'
```

Then open another terminal:

By running the following command, you can get a quick view of the CPU usage:

```bash
watch -n 2 "kubectl top pod -l app=example2 --containers"
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

## 5.Testing HPA

Running command to bring up HPA:

```bash
kubectl apply -f ./hpa_config/hpa.k3s.yaml
```

check if succeeded:

```bash
kubectl get hpa example2-hpa
kubectl describe hpa example2-hpa
```

With same technique used above, running the following command to generate requests:

```bash
kubectl run -it --rm loadgen --restart=Never --image=busybox:1.28 -- \
  sh -c 'while true; do wget -q -O- http://example2 >/dev/null; done'
```

In another terminal, monitor the change by running:

```bash
kubectl get hpa example2-hpa --watch
```

with more load:

```bash
kubectl run -it --rm fortio --image=fortio/fortio --restart=Never -- \
  load -t 300s -c 10 -qps 2000 -loglevel Error http://example2
```

-c 10 = 10 workers/connections

-qps 2000 = Fortio tries to send 2000 HTTP requests per second overall (not per connection)

[⬅ Back to README](README.md)