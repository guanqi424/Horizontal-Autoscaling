# Feb 4 2026 - Setting HPA using K3s

## Requirements (dependencies): docker, kubectl, kind, [k3d](https://github.com/k3d-io/k3d)

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

#### k3d

You have several options there:

- use the install script to grab the latest release:
    - wget: `wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`
    - curl: `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`
- use the install script to grab a specific release (via `TAG` environment variable):
    - wget: `wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.0.0 bash`
    - curl: `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.0.0 bash`

- use [Homebrew](https://brew.sh): `brew install k3d` (Homebrew is available for MacOS and Linux)
    - Formula can be found in [homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core/blob/master/Formula/k3d.rb) and is mirrored to [homebrew/linuxbrew-core](https://github.com/Homebrew/linuxbrew-core/blob/master/Formula/k3d.rb)
- install via [MacPorts](https://www.macports.org): `sudo port selfupdate && sudo port install k3d` (MacPorts is available for MacOS)
- install via [AUR](https://aur.archlinux.org/) package [rancher-k3d-bin](https://aur.archlinux.org/packages/rancher-k3d-bin/): `yay -S rancher-k3d-bin`
- grab a release from the [release tab](https://github.com/k3d-io/k3d/releases) and install it yourself.
- install via go: `go install github.com/k3d-io/k3d/v5@latest` (**Note**: this will give you unreleased/bleeding-edge changes)
- use [Chocolatey](https://chocolatey.org/): `choco install k3d` (Chocolatey package manager is available for Windows)
    - package source can be found in [erwinkersten/chocolatey-packages](https://github.com/erwinkersten/chocolatey-packages/tree/master/automatic/k3d)
- use [Scoop](https://scoop.sh/): `scoop install k3d` (Scoop package manager is available for Windows)
    - package source can be found in [ScoopInstaller/Main](https://github.com/ScoopInstaller/Main/blob/master/bucket/k3d.json)

##### Usage

Check out what you can do via `k3d help` or check the docs @ [k3d.io](https://k3d.io)

Example Workflow: Create a new cluster and use it with `kubectl`

1. `k3d cluster create CLUSTER_NAME` to create a new single-node cluster (= 1 container running k3s + 1 loadbalancer container)
2. [Optional, included in cluster create] `k3d kubeconfig merge CLUSTER_NAME --kubeconfig-switch-context` to update your default kubeconfig and switch the current-context to the new one
3. execute some commands like `kubectl get pods --all-namespaces`
4. `k3d cluster delete CLUSTER_NAME` to delete the default cluster

## 1.install k3s(MacOS)

```bash
brew install kubectl kind k3d
```

## 2.create cluster

```yaml
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: k3sTest
servers: 1
agents: 0
ports:
  # hostPort 81  -->  nodePort 30090 on the (only) server node
  - port: "81:30090"
    nodeFilters:
      - "server:0"
options:
  k3s:
    extraArgs:
      - arg: "--kube-controller-manager-arg=horizontal-pod-autoscaler-sync-period=5s"
        nodeFilters:
          - "server:0"
      # optional: reduce global scale-down stabilization (default is 5m)
      # - arg: "--kube-controller-manager-arg=horizontal-pod-autoscaler-downscale-stabilization=60s"
      #   nodeFilters:
      #     - "server:0"
```

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

## 3.deploying pods

Before deploying, see if you're in the right cluster. If not, switch to the correct cluster using command:

```bash
kubectl config get-contexts
kubectl config use-context k3d-k3sTest
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example2
  labels:
    app: example2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example2
  template:
    metadata:
      labels:
        app: example2
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - name: http
              containerPort: 80
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
```

running command to deploy pods: 

```bash
kubectl apply -f ./deploy_config/deploy.k3s.yaml
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
  name: example2
  labels:
    app: example2
spec:
  type: NodePort
  selector:
    app: example2
  ports:
    - protocol: TCP
      targetPort: 80
      port: 80
      nodePort: 30090
```

Run this command:

```bash
kubectl apply -f ./deploy_config/service.k3s.yaml
```

After completion, visit: [http://localhost:81](http://localhost:81) , you can see nginx service running.

You can also check via running the following command to see more details:

```bash
kubectl get services
```

## 4.Metrics Server
k3s typically deploys metrics-server as a packaged component (unless you disable it), so HPA usually works without the “metrics-server install” dance you sometimes do in other local clusters.

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

The IP address is the same as we set in the service.k8s.yaml:

```yaml
metadata:
  name: example2
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

Using the following YAML:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: example2-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: example2
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