# DevOps Screening Challenge

## Overview

This challenge runs entirely on your local machine using Docker and KIND (Kubernetes in Docker). The Terraform stack will install dependencies, create a local KIND cluster, and deploy broken workloads for you to debug.

## Prerequisites

- **OS:** Ubuntu/Debian-based Linux (scripts use `apt-get`)
- **Docker:** Will be installed by the setup scripts if not present
- **Terraform:** v0.13+ (install locally)
- **sudo access:** Required for installing packages and tools

## Setup

1. Clone this repository:
   ```bash
   git clone git@github.com:sanjay-fiftyfive/devops-hiring-assignment.git
   cd devops-hiring-assignment
   ```

2. Deploy the environment using Terraform:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

   This will:
   - Install Docker, kubectl, and KIND locally
   - Create a 4-node KIND cluster (1 control-plane + 3 workers)
   - Deploy all challenge workloads
   - Apply sabotage to create the debugging challenges

3. Verify the cluster is running:
   ```bash
   kubectl --context kind-sanjay-challenge get nodes
   ```

## Rules

1. You **MAY NOT** modify the existing Terraform code or Kubernetes manifests that deploy the initial cluster. If the initial deployment fails, you may debug and fix it.
2. You **may install** anything you need on your local machine.
3. **Document your work** — for each challenge, create a file `solution-N.md` describing:
   - What symptoms you observed
   - What tools you used to investigate
   - What the root cause was and how you confirmed it
   - What you did to fix it
   - How you verified the fix

## Time Limit

- **Total: 4 hours**
- Suggested pace: 20 / 30 / 40 / 45 / 45 / 50 minutes per challenge
- Partial solutions are valued — show your debugging process

---

## Challenges

### Challenge 1: Deploy the Cluster

Deploy the Terraform stack in the `terraform/` directory to create a KIND cluster on your local machine.

The Terraform code has issues that will prevent a successful deployment. Debug and fix them to get the cluster running.

After deployment you should have:
- A 4-node KIND cluster (1 control-plane + 3 workers)
- kubectl access via context `kind-sanjay-challenge`

Verify: `kubectl --context kind-sanjay-challenge get nodes`

*Hint: Start with `terraform init` and work through the errors one at a time. There are multiple issues across different Terraform concepts.*

---

### Challenge 2: Fix the Broken Deployment

In namespace **t2**, the deployment `task-2` wants **3 healthy replicas** but all pods are failing.

**Goal:** Get all 3 replicas of `task-2` running and ready.

*Hint: There are multiple issues. The first fix won't be the last.*

---

### Challenge 3: Network Black Hole

In namespace **t3**, there is a deployment `task-3` running a standard nginx server with a service exposing port 80.

In the **default** namespace, a pod `debug-client` (with full networking tools) has been deployed.

**Goal:** From inside `debug-client`, successfully run:
```bash
curl http://task-3.t3.svc.cluster.local
```
It should return the nginx welcome page.

*Hint: There are multiple layers blocking connectivity. The obvious one isn't the only one.*

---

### Challenge 4: Node Recovery

Node `sanjay-challenge-worker2` has gone **NotReady**.

**Goal:** Bring the node back to `Ready` status and ensure it can schedule and run pods.

*Hint: You'll need to get inside the node's container to debug. The node runs as a Docker container — use `docker exec` to access it. The issue is not a single problem.*

---

### Challenge 5: TLS Certificate Debugging

In namespace **t5**, there is a deployment `secure-app` running nginx configured for HTTPS on port 443, and a pod `tls-client` with curl installed.

A CA bundle is mounted at `/etc/ssl/custom/ca.crt` inside the `tls-client` pod.

**Goal:** Make this command succeed **without** using `--insecure` or `-k`:
```bash
kubectl exec tls-client -n t5 -- curl --cacert /etc/ssl/custom/ca.crt https://secure-app.t5.svc.cluster.local
```
It must return: `TLS Challenge Complete!`

*Hint: There are multiple certificate-related issues. The server may not even start initially.*

---

### Challenge 6: Performance Triage Under Load

In namespace **t6**, the deployment `api-server` is experiencing intermittent failures. A `load-generator` pod is sending continuous traffic to the service.

**Rules:**
- Do **NOT** stop or delete the `load-generator` pod
- Do **NOT** reduce the load generator's request rate

**Goal:** Make the `api-server` handle all requests successfully with response times under 2 seconds. An HPA is configured but isn't working.

*Hint: There are resource constraints at multiple levels. Check what's limiting scaling.*

---

## Tools You Should Know

| Tool | Usage |
|------|-------|
| `kubectl` | Cluster interaction, pod debugging, log reading |
| `docker exec` | Access KIND node containers |
| `systemctl` / `journalctl` | Linux service management inside nodes |
| `tcpdump` / `nslookup` / `dig` | Network and DNS debugging |
| `openssl` | TLS certificate inspection |
| `iptables` | Firewall rule inspection |
| `strace` | System call tracing |
| `df` / `htop` / `top` | Resource monitoring |

## Cleanup

To tear down the entire environment:
```bash
kind delete cluster --name sanjay-challenge
```

Or to destroy everything Terraform created:
```bash
cd terraform
terraform destroy
```

## Submission

When complete:
1. Ensure all fixes are applied on the cluster
2. Your `solution-N.md` files describe your debugging process
3. **Record a Loom video** (15-20 minutes) walking through your solutions:
   - Briefly explain each challenge and what you found
   - Show the fix in action (e.g., run the verification commands live)
   - Highlight your debugging approach — what tools you used and why
   - Share the Loom link along with your solution files

**Note:** Keep your local environment running after submission. In the next round, you will be asked to perform additional tasks on the same cluster in a live session.
