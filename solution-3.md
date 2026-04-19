# Challenge 3: Network Connectivity and DNS Issues

## Symptoms Observed

Service communication issues in Kubernetes cluster preventing debug client from reaching services:

1. **Debug pod missing** - No debug-client pod found in default namespace
2. **DNS resolution failures** - Could not resolve service hostname `task-3.t3.svc.cluster.local`
3. **Network policy blocking egress** - All outbound traffic blocked from default namespace
4. **Network policy blocking ingress** - All inbound traffic blocked to t3 namespace


## Tools Used to Investigate

- `kubectl get pods -n <namespace>` - Check pod existence and status
- `kubectl exec -it <pod> -- <command>` - Execute commands in containers
- `curl` - Test HTTP connectivity and DNS resolution
- `kubectl describe networkpolicy` - Inspect network policies
- `kubectl get networkpolicy -A` - List all network policies
- `kubectl describe node` - Check node status and conditions
- `kubectl get nodes` - View cluster node health
- `docker exec -it <node> bash` - Access Kind node containers

## Root Causes and Confirmation

### Issue 1: Debug Client Pod Not Created

**Root Cause:**
The debug-client pod was never created in the default namespace.

**Confirmation:**
```bash
kubectl get pods -n default
# No resources found in default namespace.
```

### Issue 2: DNS Resolution Failure (CoreDNS Misconfiguration)

**Root Cause:**
CoreDNS ConfigMap had an invalid rewrite rule redirecting `task-3.t3.svc.cluster.local` to non-existent domain `task-3.t3.svc.cluster.invalid`.

**Confirmation:**
```bash
kubectl exec -it debug-client -n default -- curl http://task-3.t3.svc.cluster.local
# curl: (6) Could not resolve host: task-3.t3.svc.cluster.local (Timeout while contacting DNS servers)

kubectl exec -it debug-client -n default -- nslookup task-3.t3.svc.cluster.local
# Server timeout or NXDOMAIN response
```

Checked CoreDNS configuration:
```bash
kubectl get configmap coredns -n kube-system -o yaml
```

Found malicious rewrite rule:
```yaml
rewrite name task-3.t3.svc.cluster.local task-3.t3.svc.cluster.invalid
```

### Issue 3: Egress Network Policy Blocking Outbound Traffic

**Root Cause:**
Network policy `deny-all-egress` in default namespace blocked all outbound connections.

**Confirmation:**
```bash
kubectl describe networkpolicy deny-all-egress -n default
```

Output:
```
Name:         deny-all-egress
Namespace:    default
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Not affecting ingress traffic
  Allowing egress traffic:
    <none> (Selected pods are isolated for egress connectivity)
```

This policy blocked all egress traffic from pods in the default namespace.

### Issue 4: Ingress Network Policy Blocking Inbound Traffic

**Root Cause:**
Network policy `deny-all-ingress` in t3 namespace blocked all inbound connections to services.

**Confirmation:**
```bash
kubectl describe networkpolicy deny-all-ingress -n t3
# Similar configuration blocking all ingress to t3 namespace
```


## Fixes Applied

### Fix 1: Created Debug Client Pod

**Created pod with proper labels:**
```bash
kubectl run debug-client \
  --image=nicolaka/netshoot \
  -n default \
  --labels='role=debug-client' \
  -- sleep infinity
```

**Verification:**
```bash
kubectl get pods -n default
# NAME           READY   STATUS    RESTARTS   AGE
# debug-client   1/1     Running   0          10s
```

### Fix 2: Restored CoreDNS Configuration

**Removed malicious rewrite rule:**
```bash
kubectl edit configmap coredns -n kube-system
```

Deleted line:
```yaml
rewrite name task-3.t3.svc.cluster.local task-3.t3.svc.cluster.invalid
```

**Restarted CoreDNS pods:**
```bash
kubectl -n kube-system delete pods -l k8s-app=kube-dns
```

### Fix 3: Deleted Egress Network Policy

**Removed blocking egress policy:**
```bash
kubectl delete networkpolicy deny-all-egress -n default
```

### Fix 4: Deleted Ingress Network Policy

**Removed blocking ingress policy:**
```bash
kubectl delete networkpolicy deny-all-ingress -n t3
```





## Verification Steps

### 1. Verified Debug Pod Creation
```bash
kubectl get pods -n default
# NAME           READY   STATUS    RESTARTS   AGE
# debug-client   1/1     Running   0          5m

kubectl get pods -n default --show-labels
# NAME           READY   STATUS    LABELS
# debug-client   1/1     Running   role=debug-client
```

### 2. Verified DNS Resolution
```bash
kubectl exec -it debug-client -n default -- nslookup task-3.t3.svc.cluster.local
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# 
# Name:      task-3.t3.svc.cluster.local
# Address 1: 10.96.x.x task-3.t3.svc.cluster.local
```

### 3. Verified Network Connectivity
```bash
kubectl exec -it debug-client -n default -- curl http://task-3.t3.svc.cluster.local
# Successfully retrieved response from service
# HTTP 200 OK
```

### 4. Verified Network Policies Removed
```bash
kubectl get networkpolicy -n default
# No resources found in default namespace.

kubectl get networkpolicy -n t3
# No resources found in t3 namespace.
```





## Summary

All network connectivity and node issues were successfully resolved:
- ✅ Debug client pod created with proper configuration
- ✅ CoreDNS restored with malicious rewrite rule removed
- ✅ Egress network policy deleted from default namespace
- ✅ Ingress network policy deleted from t3 namespace
- ✅ DNS resolution working correctly for cluster services