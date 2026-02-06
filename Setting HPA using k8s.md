# Feb 4 2026 - Setting HPA using K8s

## Requirements (dependencies): docker, kubectl, kind

#### Docker

To get `kind` working you will need docker installed.

* On Linux it is best to use your operating system package manager, `apt` on ubuntu or debian, `yum` or `dnf` on Fedora/Centos/RHEL and `pacman` or `yay` on Archlinux.
* On Mac or Windows use the instructions for your platform on [dockers documentation](https://docs.docker.com/get-docker/)

#### Kubectl

You will also need the `kubectl` command to interact with the cluster once it's up and running.

* On Linux install the [kubectl install instructions](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-linux) are available, including methods to install it with your Linux distributions' packages manager, but it can be installed easily with the following commands:

  ```bash
  curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt` /bin/linux/amd64/kubectl
  chmod +x ./kubectl
  sudo mv ./kubectl /usr/local/bin/kubectl
  ```

* On a Mac, it should be easy if you use the `brew` package manager, just run `brew install kubectl`. Further instructions for MacOs are available here in [Kubernetes MacOs kubectl installation instructions](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-macos)
* On Windows, of course instructions are also available on the [Kubernetes kubectl installation instructions page](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-on-windows)

#### KIND

Finally, you will need to get the `kind` command.

* On Linux or Mac you can install it from the projects [github releases page](https://github.com/kubernetes-sigs/kind/releases), much like the `kubectl` binary, with these commands:

  ```bash
  curl -L https://github.com/kubernetes-sigs/kind/releases/download/v0.8.1/kind-linux-amd64 -o kind
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
  ```

* On a Mac, alternatively it can be installed easily using the `brew` command again, with:

  ```bash
  brew install kind
  ```

* On Windows either use curl if you have it available:

  ```bash
  curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.8.1/kind-windows-amd64
  Move-Item .\kind-windows-amd64.exe c:\some-dir-in-your-PATH\kind.exe
  ```

  Or use the [Chocolatey package manager for windows](https://chocolatey.org/):

  ```bash
  choco install kind
  ```

For full up to date instructions on any of these kind installation methods, see the projects [Quick Start Guide](https://kind.sigs.k8s.io/docs/user/quick-start/).


## 1.	create a cluster

with YAML file:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: cluster
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30060
        hostPort: 80
        listenAddress: "0.0.0.0"
        protocol: TCP
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiVersion: kubeadm.k8s.io/v1beta3
        controllerManager:
          extraArgs:
            horizontal-pod-autoscaler-sync-period: "5s"
            # horizontal-pod-autoscaler-downscale-stabilization: "60s"
```

and command:

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

Setting up deployment YAML:

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
         requests:              # The scheduler uses requests to decide which node has enough capacity to place the pod.
           cpu: 100m            # 0.1 CPU core (100 millicores)
           memory: 128Mi        # 128 MiB
         limits:                # The maximum the container is allowed to use.
           cpu: 500m            # 0.5 CPU core (500 millicores)
           memory: 256Mi        # 256 MiB
       ports:
       - containerPort: 80
         name: nginx
```

running command to deploy pods: 

```bash
kubectl apply -f ./deploy_config/deploy.k8s.yaml
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
      nodePort: 30060
```

Run this command:

```bash
kubectl apply -f ./deploy_config/service.k8s.yaml
```

After completion, visit: [http://localhost:8080](http://localhost:8080) , you can see nginx service running.

You can also check via running the following command to see more details:

```bash
kubectl get services
```

## 3.	Install Metrics Server

Install Metrics Server(every time you create a new cluster):

```bash
kubectl apply -f ./metricsServer_config/metrics_service.yaml
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

The IP address is the same as we set in the service.k8s.yaml:

```yaml
metadata:
  name: example1
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
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
    #      selectPolicy: Max # Default is Max. Max: choose the policy that allows the biggest change (faster); Min: choose the policy that allows the smallest change (slower)
    #      policies:
    #        - type: Percent
    #          value: 100        # up to +100% per minute (double)
    #          periodSeconds: 60
    #        - type: Pods
    #          value: 4          # or at most +4 per minute
    #          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 5
#      selectPolicy: Min
#      policies:
#        - type: Percent
#          value: 20         # shrink slowly
#          periodSeconds: 60
#        - type: Pods
#          value: 1
#          periodSeconds: 60
```

and running command to set up HPA:

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
