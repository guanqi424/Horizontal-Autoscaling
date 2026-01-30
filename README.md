# How to run HPA

### Precondition: docker, kubectl, kind

## 1.	create a cluster

with YAML file:

```yaml
# Save this to 'kind.config.yaml'
kind: Cluster
apiVersion: kind.sigs.k8s.io/v1alpha3
nodes:
- role: control-plane
 extraPortMappings:
 - containerPort: 30080
   hostPort: 80
   listenAddress: "0.0.0.0"
   protocol: TCP
```

and command:

```bash
kind create cluster --name mycluster --config cluster_config/kind.config.yaml --wait 5m
```

## 2.	deploying pods and expose service

setting up deployment YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
 labels:
   app: example1
 name: example1
spec:
 replicas: 1
 selector:
   matchLabels:
     app: example1
 template:
   metadata:
     labels:
       app: example1
   spec:
     containers:
     - image: nginx:latest
       name: nginx
       resources:
         requests:
           cpu: 100m
           memory: 128Mi
         optional:
         limits:
           cpu: 500m
           memory: 256Mi
       ports:
       - containerPort: 80
         name: nginx
```

running command to deploy pods: 

```bash
kubectl apply -f ./deploy_config/deploy1.yaml
```

check by running : 
```bash
kubectl get pods
```

Using this YAML:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: example1
  labels:
    app: example1
spec:
  type: NodePort
  selector:
    app: example1
  ports:
    - protocol: TCP
      targetPort: 80
      port: 80
      nodePort: 30080
```

Run this command:

```
kubectl apply -f ./deploy_config/service.yaml
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

The IP address is the same as we set in the service.yaml:

```yaml
metadata:
  name: example1
```

Then open another terminal:

By running the following command, you can get a quick view of the CPU usage:

```bash
watch -n 2 "kubectl top pod -l app=example1 --containers"
```

Or running the following command to to get a more continues view and store the data into  a file:

```bash
for i in $(seq 1 60); do
  date -u +"%Y-%m-%dT%H:%M:%SZ"
  kubectl top pod -l app=example1  --containers --no-headers
  echo "---"
  sleep 5
done | tee nginx-metrics-samples.txt
```

## 5.	Testing HPA

Using the following YAML:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: example1-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: example1
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

and running command to set up HPA:

```bash
kubectl apply -f ./hpa_config/hpa.yaml
```

check if succeed:

```bash
kubectl get hpa example1-hpa
kubectl describe hpa example1-hpa
```

With same technique used above, running the following command to generate requests:

```bash
kubectl run -it --rm loadgen --restart=Never --image=busybox:1.28 -- \
  sh -c 'while true; do wget -q -O- http://example1 >/dev/null; done'
```

with more load:

```bash
kubectl run -it --rm fortio --image=fortio/fortio --restart=Never -- \
  load -t 300s -c 10 -qps 2000 -loglevel Error http://example1
```

-c 10 = 10 workers/connections
-qps 2000 = Fortio tries to send 2000 HTTP requests per second overall (not per connection)

In another terminal, monitor the change by running:

```bash
kubectl get hpa example1-hpa --watch
```


##### Horizontal-Autoscaling
##### updated on Jan 30 2026
