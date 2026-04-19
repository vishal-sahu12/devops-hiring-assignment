# Challenge 4: Node and Storage Issues

## Symptoms Observed

### Issue: Node sanjay-challenge-worker2 Unavailable
- Node status showing as `NotReady` and `SchedulingDisabled`
- Pods unable to schedule on the affected node
- Node appeared in the cluster but was not accepting workloads
- Multiple taints present on the node preventing pod scheduling

### Specific Error Indicators
```
Node: sanjay-challenge-worker2
Status: NotReady, SchedulingDisabled

Taints:
- node.kubernetes.io/unreachable
- node.kubernetes.io/unschedulable
```

## Tools Used for Investigation

### Kubernetes Investigation Tools
- `kubectl get nodes` - To check overall node status
- `kubectl describe node sanjay-challenge-worker2` - To get detailed node information including taints and conditions
- `kubectl get pods -A` - To verify pod distribution across nodes

### Node-Level Investigation Tools
- `docker exec -it sanjay-challenge-worker2 bash` - To access the node container
- `df -h` - To check disk space usage on the node
- `systemctl status kubelet` - To check kubelet service status
- `journalctl -u kubelet` - To examine kubelet logs for errors
- `ls -la /var/lib/kubelet/pki/` - To check kubelet certificate files

## Root Causes Identified

### Root Cause 1: Disk Space Exhaustion
**Root Cause**: A large file `/var/log/bloat.img` was consuming excessive disk space, preventing kubelet from functioning properly.

**Confirmation**: 
```bash
docker exec -it sanjay-challenge-worker2 bash
df -h
# Output showed /var/log partition nearly full
ls -lh /var/log/bloat.img
# Showed large file consuming significant space
```

The kubelet requires adequate disk space to:
- Store container logs
- Download and store container images
- Maintain pod state files
- Write temporary files

### Root Cause 2: Corrupted Kubelet Client Certificate
**Root Cause**: The kubelet client certificate at `/var/lib/kubelet/pki/kubelet-client-current.pem` was corrupted or missing, preventing the kubelet from authenticating with the Kubernetes API server.

**Confirmation**:
```bash
journalctl -u kubelet | grep -i certificate
# Showed certificate-related authentication errors

ls -la /var/lib/kubelet/pki/
# Found kubelet-client-current.pem.bak backup file present
```

A valid backup existed at `kubelet-client-current.pem.bak`, indicating the original certificate had been backed up before corruption.

### Root Cause 3: Node Scheduling Disabled (Cordoned)
**Root Cause**: The node was cordoned (marked as unschedulable), preventing any new pods from being scheduled on it.

**Confirmation**:
```bash
kubectl get nodes
# Showed SchedulingDisabled status

kubectl describe node sanjay-challenge-worker2
# Showed Unschedulable: true
# Showed taints including node.kubernetes.io/unschedulable
```

## Fixes Applied

### Fix 1: Remove Disk Space Issue
Removed the bloat file consuming disk space:

```bash
# Access the node
docker exec -it sanjay-challenge-worker2 bash

# Remove the problematic file
rm -f /var/log/bloat.img

# Verify disk space freed
df -h
```

### Fix 2: Restore Kubelet Client Certificate
Restored the valid certificate from backup:

```bash
# Still inside the node container
mv /var/lib/kubelet/pki/kubelet-client-current.pem.bak \
   /var/lib/kubelet/pki/kubelet-client-current.pem

# Verify certificate restored
ls -la /var/lib/kubelet/pki/kubelet-client-current.pem
```

### Fix 3: Restart Kubelet Service
Restarted kubelet to apply certificate changes and clear errors:

```bash
# Restart the kubelet service
systemctl restart kubelet

# Verify kubelet is running
systemctl status kubelet

# Check kubelet logs for successful startup
journalctl -u kubelet -f
```

### Fix 4: Uncordon the Node
Removed the scheduling restriction from the node:

```bash
# Exit from node container back to host
exit

# Uncordon the node to allow scheduling
kubectl uncordon sanjay-challenge-worker2
```

## Verification Steps

### 1. Node Status Verification
```bash
kubectl get nodes
# Expected output:
# NAME                          STATUS   ROLES           AGE   VERSION
# sanjay-challenge-worker2      Ready    <none>          Xh    vX.XX.X
```

**Result**: Node status changed from `NotReady,SchedulingDisabled` to `Ready`

### 2. Node Taints Verification
```bash
kubectl describe node sanjay-challenge-worker2 | grep -i taint
# Expected: No taints or only standard taints (not unreachable/unschedulable)
```

**Result**: `node.kubernetes.io/unreachable` and `node.kubernetes.io/unschedulable` taints removed

### 3. Kubelet Health Verification
```bash
docker exec -it sanjay-challenge-worker2 bash
systemctl status kubelet
# Expected: active (running)

journalctl -u kubelet --since "5 minutes ago" | grep -i error
# Expected: No critical errors
```

**Result**: Kubelet running without authentication or certificate errors

### 4. Disk Space Verification
```bash
docker exec -it sanjay-challenge-worker2 bash
df -h
# Expected: Adequate free space on /var/log partition
```

**Result**: Sufficient disk space available for normal operations

### 5. Pod Scheduling Verification
```bash
# Try to schedule a test pod on the specific node
kubectl run test-pod --image=nginx --overrides='{"spec":{"nodeName":"sanjay-challenge-worker2"}}'

# Check if pod scheduled successfully
kubectl get pod test-pod -o wide
# Expected: Pod running on sanjay-challenge-worker2

# Cleanup
kubectl delete pod test-pod
```

**Result**: Pods successfully scheduled and running on the node

### 6. Overall Cluster Health
```bash
kubectl get pods -A
# Expected: All pods distributed across nodes including worker2
```

**Result**: Workloads distributed properly across all available nodes

## Lessons Learned

1. **Disk Space Monitoring**: 
   - Implement monitoring alerts for disk space usage on nodes
   - Set up log rotation policies to prevent disk exhaustion
   - Regular cleanup of old container logs and images

2. **Certificate Management**:
   - Always maintain valid backups of critical certificates
   - Implement certificate expiration monitoring
   - Document certificate restoration procedures

3. **Node Maintenance**:
   - Drain nodes properly before maintenance (don't just cordon)
   - Document why nodes are cordoned
   - Set up automated uncordoning after maintenance completion

4. **Troubleshooting Workflow**:
   - Check node status first with `kubectl get nodes`
   - Use `kubectl describe node` for detailed diagnostics
   - Access node directly for system-level issues
   - Check kubelet logs for service-specific problems
   - Verify disk space and certificates as common failure points

5. **Recovery Procedures**:
   - Fix issues in order: disk space → certificates → services → scheduling
   - Restart services after certificate changes
   - Verify each fix before proceeding to the next
   - Test pod scheduling after node recovery