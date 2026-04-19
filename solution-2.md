# Challenge 2: Kubernetes Pod Scheduling and Deployment Issues

## Symptoms Observed

Deployment in namespace `t2` was experiencing multiple issues preventing pods from running:

1. **Pod scheduling failures** - Pods stuck in Pending state with FailedScheduling events
2. **Node selector mismatch** - No nodes matching `disk=ssd` label requirement
3. **Unschedulable nodes** - Worker nodes in SchedulingDisabled state
4. **Image pull failures** - ErrImagePull and ImagePullBackOff errors
5. **Readiness probe failures** - Pods failing health checks
6. **Resource quota violations** - Insufficient pod quota in namespace

## Tools Used to Investigate

- `kubectl get pods -n t2` - Check pod status
- `kubectl describe pod <pod-name> -n t2` - Detailed pod event inspection
- `kubectl get nodes --show-labels` - Verify node labels
- `kubectl get nodes` - Check node status and schedulability
- `kubectl describe deployment -n t2` - Check deployment configuration
- `kubectl get resourcequota -n t2` - Check namespace resource quotas
- `kubectl logs <pod-name> -n t2` - Check container logs

## Root Causes and Confirmation

### Issue 1: Node Selector Not Matching Any Nodes

**Root Cause:**
Deployment specified `nodeSelector: disk=ssd` but no worker nodes had this label applied.

**Confirmation:**
```bash
kubectl describe pod task-2-759f5fbfb4-7jg4v -n t2
```

Output showed:
```
Node-Selectors:              disk=ssd
Events:
  Warning  FailedScheduling  0/4 nodes are available: 1 node(s) didn't match Pod's node affinity/selector, 
                             1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 
                             2 node(s) were unschedulable.
```

Checked node labels:
```bash
kubectl get nodes --show-labels | grep disk
# No output - no nodes with disk=ssd label
```

### Issue 2: Incorrect Container Image Tag (Typo)

**Root Cause:**
Image specified as `nginx:1.19-alpne` (typo: "alpne" instead of "alpine")

**Confirmation:**
```bash
kubectl describe pod task-2-759f5fbfb4-7jg4v -n t2
```

Events showed:
```
Warning  Failed  Failed to pull image "nginx:1.19-alpne": rpc error: code = NotFound 
                 desc = failed to pull and unpack image "docker.io/library/nginx:1.19-alpne": 
                 docker.io/library/nginx:1.19-alpne: not found
Warning  Failed  Error: ErrImagePull
Warning  Failed  Error: ImagePullBackOff
```

### Issue 3: Incorrect Readiness Probe Path

**Root Cause:**
Readiness probe configured with path `/healthz` but nginx default doesn't serve this endpoint.

**Confirmation:**
```bash
kubectl describe pod -n t2
```

Output showed:
```
readinessProbe:
  httpGet:
    path: /healthz
    port: 80
```

Nginx returns 404 for `/healthz` causing readiness failures. Default nginx serves content at `/`.

### Issue 4: ResourceQuota Limiting Pod Count

**Root Cause:**
Namespace had ResourceQuota limiting pods to 2, but deployment required 3 replicas.

**Confirmation:**
```bash
kubectl get resourcequota -n t2
```

Output:
```
NAME          AGE   REQUEST      LIMIT
tight-quota   22h   pods: 2/2
```

Deployment spec required 3 pods but quota only allowed 2.

## Fixes Applied

### Fix 1: Added Missing Node Label

**Applied label to worker node:**
```bash
kubectl label nodes sanjay-challenge-worker3 disk=ssd
```

**Verification:**
```bash
kubectl get nodes --show-labels | grep disk=ssd
# sanjay-challenge-worker3   Ready    <none>   disk=ssd
```

### Fix 2: Uncordoned Unschedulable Nodes

**Made nodes schedulable again:**
```bash
kubectl uncordon sanjay-challenge-worker
```

**Verification:**
```bash
kubectl get nodes
# All worker nodes now show Ready,SchedulingEnabled
```

### Fix 3: Corrected Container Image Tag

**Updated deployment in main.tf:**
```hcl
# From:
image = "nginx:1.19-alpne"

# To:
image = "nginx:1.19-alpine"
```

**Applied changes:**
```bash
terraform apply -auto-approve
```

### Fix 4: Fixed Readiness Probe Path

**Updated readiness probe in deployment configuration:**
```yaml
# From:
readinessProbe:
  httpGet:
    path: /healthz
    port: 80

# To:
readinessProbe:
  httpGet:
    path: /
    port: 80
```

### Fix 5: Removed Restrictive ResourceQuota

**Deleted the quota to allow required pods:**
```bash
kubectl delete resourcequota tight-quota -n t2
```

**Cleaned up existing pods to trigger recreation:**
```bash
kubectl delete pods -n t2 --all
```

## Verification Steps

### 1. Verified Node Labels and Schedulability
```bash
kubectl get nodes --show-labels | grep sanjay-challenge-worker3
# sanjay-challenge-worker3   Ready    <none>   23h   disk=ssd

kubectl get nodes
# All nodes show Ready status, no SchedulingDisabled
```

### 2. Verified Deployment Rollout
```bash
kubectl rollout status deployment/task-2 -n t2
# deployment "task-2" successfully rolled out

kubectl get deployment -n t2
# NAME     READY   UP-TO-DATE   AVAILABLE   AGE
# task-2   3/3     3            3           23h
```

### 3. Verified Pod Status
```bash
kubectl get pods -n t2
# NAME                      READY   STATUS    RESTARTS   AGE
# task-2-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# task-2-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# task-2-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### 4. Verified Image Pull Success
```bash
kubectl describe pod <pod-name> -n t2 | grep -A5 Events
# Normal  Pulling    Successfully pulled image "nginx:1.19-alpine"
# Normal  Created    Created container nginx
# Normal  Started    Started container nginx
```

### 5. Verified Readiness Probe
```bash
kubectl describe pod <pod-name> -n t2 | grep -A3 Readiness
# Readiness:      http-get http://:80/ delay=0s timeout=1s period=10s #success=1 #failure=3

kubectl get pods -n t2
# All pods show 1/1 READY (readiness probe passing)
```

### 6. Verified ResourceQuota Removal
```bash
kubectl get resourcequota -n t2
# No resources found in t2 namespace.

kubectl get pods -n t2 --no-headers | wc -l
# 3
```

### 7. End-to-End Service Test
```bash
kubectl run test-client --rm -it --image=busybox -n t2 -- wget -qO- task-2.t2.svc.cluster.local
# Successfully retrieved nginx welcome page
```

## Summary

All scheduling and deployment issues were successfully resolved:
- ✅ Node labeled with `disk=ssd` selector requirement
- ✅ Worker nodes uncordoned and made schedulable
- ✅ Container image corrected from `nginx:1.19-alpne` to `nginx:1.19-alpine`
- ✅ Readiness probe path changed from `/healthz` to `/`
- ✅ ResourceQuota removed to allow 3 pod replicas
- ✅ All 3 pods running, ready, and serving traffic successfully