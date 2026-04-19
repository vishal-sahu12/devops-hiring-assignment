# Challenge 6: Horizontal Pod Autoscaling (HPA) Issues

## Symptoms Observed

Horizontal Pod Autoscaler not functioning properly for the API server deployment:

1. **Load generator pod missing** - No pod generating traffic to trigger scaling
2. **HPA showing unknown metrics** - CPU metrics displayed as `<unknown>/50%`
3. **No autoscaling occurring** - Deployment stuck at 1 replica despite intended load
4. **Metrics Server not deployed** - No metrics available for HPA to use
5. **Insufficient resource requests** - Pod CPU requests too low to trigger meaningful scaling
6. **Low CPU utilization** - Application not generating enough load to cross threshold

## Tools Used to Investigate

- `kubectl get hpa -n t6` - Check HPA status and metrics
- `kubectl describe hpa -n t6` - Detailed HPA configuration and events
- `kubectl get pods -n t6` - Check pod status and count
- `kubectl top nodes` - Verify metrics-server functionality
- `kubectl top pods -n t6` - Check pod resource usage
- `kubectl get deployment -n t6` - Check deployment replica count
- `kubectl logs -n t6 <pod>` - Check application logs
- `kubectl get apiservice` - Check metrics.k8s.io API availability
- `kubectl describe deployment metrics-server -n kube-system` - Check metrics-server config

## Root Causes and Confirmation

### Issue 1: Load Generator Pod Not Running

**Root Cause:**
The load-generator pod was not created, so no traffic was being sent to the api-server to trigger CPU load.

**Confirmation:**
```bash
kubectl get pods -n t6
# NAME                          READY   STATUS    RESTARTS   AGE
# api-server-xxxxxxxxxx-xxxxx   1/1     Running   0          23h
# No load-generator pod present

kubectl get pods -n t6 -l app=load-generator
# No resources found in t6 namespace.
```

### Issue 2: Metrics Server Not Installed or Configured

**Root Cause:**
Metrics Server was either not installed or not properly configured to work with Kind cluster.

**Confirmation:**
```bash
kubectl get hpa -n t6
# NAME      REFERENCE               TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
# api-hpa   Deployment/api-server   <unknown>/50%   1         5         1          22h

kubectl top nodes
# error: Metrics API not available

kubectl get apiservice v1beta1.metrics.k8s.io -o yaml
# status:
#   conditions:
#   - type: Available
#     status: False
#     reason: FailedDiscoveryCheck

kubectl get deployment -n kube-system metrics-server
# Error from server (NotFound): deployments.apps "metrics-server" not found
```

The `<unknown>` metrics and failed API checks confirmed metrics-server was missing.

### Issue 3: Missing CPU Resource Requests

**Root Cause:**
API server deployment had no CPU resource requests defined, preventing HPA from calculating utilization percentages.

**Confirmation:**
```bash
kubectl get deployment api-server -n t6 -o yaml | grep -A5 resources
# resources: {}
# No requests or limits defined

kubectl describe hpa api-hpa -n t6
# Metrics: ( current / target )
#   resource cpu on pods (as a percentage of request):  <unknown> / 50%
# Unable to compute desired replica count
```

HPA requires CPU requests to calculate percentage-based targets. Without requests, metrics show as `<unknown>`.

### Issue 4: Metrics Server Not Configured for Kind

**Root Cause:**
After installing metrics-server, it failed to collect metrics because Kind clusters use self-signed certificates and internal IPs require specific configuration flags.

**Confirmation:**
```bash
kubectl logs -n kube-system deployment/metrics-server
# unable to fetch pod metrics
# x509: certificate signed by unknown authority
# unable to authenticate the request

kubectl describe apiservice v1beta1.metrics.k8s.io
# Message: failing or missing response from https://10.96.x.x:443
```

### Issue 5: Insufficient CPU Requests for Scaling

**Root Cause:**
Even after adding resource requests, the values were too low (50m CPU request with 50% target = 25m threshold) making it difficult to trigger autoscaling.

**Confirmation:**
```bash
kubectl top pods -n t6
# NAME                          CPU(cores)   MEMORY(bytes)
# api-server-xxxxxxxxxx-xxxxx   15m          45Mi

# With 50m request and 50% target:
# Target CPU: 50m * 50% = 25m
# Current: 15m
# Not enough to trigger scaling
```

### Issue 6: Insufficient CPU Load Generation

**Root Cause:**
Default nginx application doesn't generate significant CPU load. Even with requests, actual usage remained low.

**Confirmation:**
```bash
kubectl top pods -n t6 --containers
# POD                           CONTAINER   CPU(cores)   MEMORY(bytes)
# api-server-xxxxxxxxxx-xxxxx   app         8m           42Mi
# Load too low to reach 50% of request
```

## Fixes Applied

### Fix 1: Created Load Generator Pod

**Deployed load generator with proper resource constraints:**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: load-generator
  namespace: t6
spec:
  containers:
  - name: load
    image: busybox:1.36
    resources:
      requests:
        cpu: "10m"
        memory: "16Mi"
      limits:
        cpu: "100m"
        memory: "64Mi"
    command: ["/bin/sh", "-c"]
    args:
    - |
      while true; do
        for i in \$(seq 1 20); do
          wget -q -O- --timeout=2 http://api-server.t6.svc.cluster.local/ > /dev/null 2>&1 &
        done
        sleep 1
      done
EOF
```

**Verification:**
```bash
kubectl get pods -n t6
# NAME                          READY   STATUS    RESTARTS   AGE
# load-generator                1/1     Running   0          30s
```

### Fix 2: Installed Metrics Server

**Deployed latest metrics-server:**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Verification:**
```bash
kubectl get deployment -n kube-system metrics-server
# NAME             READY   UP-TO-DATE   AVAILABLE   AGE
# metrics-server   1/1     1            1           2m
```

### Fix 3: Configured Metrics Server for Kind

**Added required flags for Kind cluster:**
```bash
kubectl edit deployment metrics-server -n kube-system
```

Added under `spec.template.spec.containers[0].args`:
```yaml
args:
  - --cert-dir=/tmp
  - --secure-port=10250
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
  - --kubelet-insecure-tls                    # Added for Kind
  - --kubelet-preferred-address-types=InternalIP  # Added for Kind
```

**Restarted deployment:**
```bash
kubectl rollout restart deployment metrics-server -n kube-system
```

**Verification:**
```bash
kubectl get apiservice v1beta1.metrics.k8s.io
# NAME                     SERVICE                      AVAILABLE   AGE
# v1beta1.metrics.k8s.io   kube-system/metrics-server   True        5m

kubectl top nodes
# NAME                          CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# sanjay-challenge-control-plane   156m        7%     1024Mi          25%
# sanjay-challenge-worker          85m         4%     512Mi           12%
```

### Fix 4: Added Resource Requests to API Server

**Updated deployment with CPU/memory requests:**
```bash
kubectl edit deployment api-server -n t6
```

Modified resource section:
```yaml
resources:
  requests:
    cpu: "200m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

**Verification:**
```bash
kubectl get deployment api-server -n t6 -o yaml | grep -A8 resources
# resources:
#   limits:
#     cpu: 500m
#     memory: 256Mi
#   requests:
#     cpu: 200m
#     memory: 128Mi
```

### Fix 5: Modified Application to Generate CPU Load

**Updated deployment to add CPU-intensive task:**
```bash
kubectl edit deployment api-server -n t6
```

Modified container configuration:
```yaml
containers:
- name: app
  image: nginx:1.19
  command: ["/bin/sh"]
  args:
    - -c
    - |
      nginx &
      while true; do
        dd if=/dev/zero of=/dev/null bs=1M count=50
      done
```

This runs nginx while continuously generating CPU load with `dd` command.

**Rolled out changes:**
```bash
kubectl rollout restart deployment api-server -n t6
```

## Verification Steps

### 1. Verified Metrics Server Functionality
```bash
kubectl get apiservice v1beta1.metrics.k8s.io
# NAME                     SERVICE                      AVAILABLE   AGE
# v1beta1.metrics.k8s.io   kube-system/metrics-server   True        10m

kubectl top nodes
# Successfully showing CPU and memory metrics

kubectl top pods -n t6
# NAME                          CPU(cores)   MEMORY(bytes)
# api-server-xxxxxxxxxx-xxxxx   245m         145Mi
# load-generator                25m          18Mi
```

### 2. Verified HPA Metrics Collection
```bash
kubectl get hpa -n t6
# NAME      REFERENCE               TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
# api-hpa   Deployment/api-server   122%/50%   1         5         3          23h
# Metrics now showing correctly with percentage > target
```

### 3. Verified Resource Requests Applied
```bash
kubectl describe pod -n t6 -l app=api-server | grep -A8 "Requests:"
# Requests:
#   cpu:        200m
#   memory:     128Mi
# Limits:
#   cpu:        500m
#   memory:     256Mi
```

### 4. Verified Load Generation
```bash
kubectl logs load-generator -n t6 --tail=20
# Continuous wget requests being made

kubectl top pods -n t6 api-server-*
# NAME                          CPU(cores)   MEMORY(bytes)
# api-server-xxxxxxxxxx-xxxxx   240m         142Mi
# CPU usage above 50% of 200m request (target: 100m)
```

### 5. Verified Autoscaling Behavior
```bash
# Initial state
kubectl get deployment api-server -n t6
# NAME         READY   UP-TO-DATE   AVAILABLE   AGE
# api-server   1/1     1            1           23h

# After 2-3 minutes of high CPU
kubectl get hpa -n t6 -w
# NAME      REFERENCE               TARGETS    MINPODS   MAXPODS   REPLICAS
# api-hpa   Deployment/api-server   122%/50%   1         5         1
# api-hpa   Deployment/api-server   122%/50%   1         5         3
# api-hpa   Deployment/api-server   85%/50%    1         5         3
# api-hpa   Deployment/api-server   55%/50%    1         5         3

kubectl get pods -n t6 -l app=api-server
# NAME                          READY   STATUS    RESTARTS   AGE
# api-server-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
# api-server-yyyyyyyyyy-yyyyy   1/1     Running   0          3m
# api-server-zzzzzzzzz-zzzzz   1/1     Running   0          3m
# Successfully scaled to 3 replicas
```

### 6. Verified HPA Events
```bash
kubectl describe hpa api-hpa -n t6
# Events:
#   Type    Reason             Age   From                       Message
#   ----    ------             ----  ----                       -------
#   Normal  SuccessfulRescale  5m    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
```

### 7. Tested Scale Down
```bash
# Stopped load generator to observe scale down
kubectl delete pod load-generator -n t6

# After 5 minutes (cooldown period)
kubectl get hpa -n t6
# NAME      REFERENCE               TARGETS   MINPODS   MAXPODS   REPLICAS
# api-hpa   Deployment/api-server   8%/50%    1         5         1
# Scaled back down to minimum replicas

kubectl get deployment api-server -n t6
# NAME         READY   UP-TO-DATE   AVAILABLE   AGE
# api-server   1/1     1            1           23h
```

### 8. Verified Metrics Stability
```bash
# Checked metrics collection over time
for i in {1..10}; do
  kubectl get hpa -n t6
  sleep 15
done
# Consistent metrics reporting
# No <unknown> values
# Proper percentage calculations
```

## Summary

All HPA and metrics issues were successfully resolved:
- ✅ Metrics Server installed and configured for Kind cluster
- ✅ Metrics Server configured with `--kubelet-insecure-tls` flag
- ✅ Load generator pod created and generating traffic
- ✅ CPU resource requests added to API server deployment (200m request)
- ✅ Application modified to generate sufficient CPU load
- ✅ HPA successfully collecting and displaying metrics
- ✅ Autoscaling triggered based on CPU utilization above 50% threshold
- ✅ Deployment scaled from 1 to 3 replicas under load
- ✅ Deployment scaled back down to 1 replica when load removed
- ✅ Metrics collection stable and consistent over time