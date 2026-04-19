# Challenge 1: Terraform and Kind Cluster Setup

## Symptoms Observed

While attempting to initialize and apply Terraform configuration for Kind cluster setup, encountered multiple errors:

1. **Terraform initialization failure** - Version constraint errors during `terraform init`
2. **Provider resolution errors** - HashiCorp null provider version mismatch
3. **Variable name inconsistencies** - Wrong variable names in configuration
4. **Script execution failures** - Unable to execute setup scripts with "not found" and "no such file or directory" errors

## Tools Used to Investigate

- `terraform init` - To identify version and provider issues
- `terraform validate` - To check configuration syntax
- `cat` and `less` - To examine Terraform configuration files
- `file` command - To check file line endings
- `dos2unix` - To fix Windows line ending issues

## Root Causes and Confirmation

### Issue 1: Unsupported Terraform Core Version

**Root Cause:**
```hcl
required_version = ">= 2.0.0"
```
- Terraform 2.x does not exist yet
- Installed version (1.14.3) cannot satisfy this constraint

**Confirmation:**
```bash
terraform version
# Terraform v1.14.3
```

### Issue 2: Provider Version Resolution Failure

**Root Cause:**
```hcl
version = "~> 4.0"
```
- HashiCorp null provider version 4.x does not exist
- Available versions are in the 3.x range

**Confirmation:**
Error message clearly stated: "no available releases match the given constraints ~> 4.0"

### Issue 3: Wrong Configuration and Variable Names

**Root Cause:**
Two variable name mismatches in `main.tf`:

Line 36:
```hcl
kind_config = sha256(file("${path.module}/../kubernetes/cluster-config.yaml"))
```
Should reference `kind-config-yaml` instead of non-existent file

Line 42:
```hcl
kind create cluster --name ${var.cluster_name} --config ${var.kube_config_path}
```
Should use `var.kind_config_path` instead of `var.kube_config_path`

**Confirmation:**
Terraform plan showed resource recreation on every apply due to incorrect file path

### Issue 4: Script Execution Failures

**Root Cause:**
Scripts had Windows-style line endings (CRLF) causing:
- `/bin/sh: 1: ../scripts/install-docker.sh: not found` (exit status 127)
- `no such file or directory` errors
- Carriage return characters (`\r`) in context names

**Confirmation:**
```bash
file ../scripts/*.sh
# ../scripts/install-docker.sh: ASCII text, with CRLF line terminators
```

## Fixes Applied

### Fix 1: Corrected Terraform Version Constraint

**Changed in version configuration:**
```hcl
# From:
required_version = ">= 2.0.0"

# To:
required_version = ">= 1.14.0"
```

### Fix 2: Corrected Provider Version

**Changed in provider configuration:**
```hcl
# From:
version = "~> 4.0"

# To:
version = "~> 3.0"
```

### Fix 3: Fixed Variable Names

**Line 36 - Corrected file reference:**
```hcl
# From:
kind_config = sha256(file("${path.module}/../kubernetes/cluster-config.yaml"))

# To:
kind_config = sha256(file("${path.module}/../kubernetes/kind-config.yaml"))
```

**Line 42 - Corrected variable name:**
```hcl
# From:
kind create cluster --name ${var.cluster_name} --config ${var.kube_config_path}

# To:
kind create cluster --name ${var.cluster_name} --config ${var.kind_config_path}
```

### Fix 4: Converted Line Endings

**Applied dos2unix conversion:**
```bash
dos2unix ../scripts/*.sh
dos2unix main.tf
```

This removed Windows carriage return characters and made scripts executable on Linux systems.

## Verification Steps

### 1. Verified Terraform Initialization
```bash
terraform init
# Success: Initializing provider plugins...
# Success: Terraform has been successfully initialized!
```

### 2. Validated Configuration
```bash
terraform validate
# Success: The configuration is valid.
```

### 3. Verified Provider Installation
```bash
terraform providers
# provider[registry.terraform.io/hashicorp/null] ~> 3.0
```

### 4. Checked Script Executability
```bash
file ../scripts/*.sh
# ../scripts/install-docker.sh: Bourne-Again shell script, ASCII text executable

bash -n ../scripts/install-docker.sh
# No syntax errors reported
```

### 5. Applied Terraform Configuration
```bash
terraform plan
# No errors, plan shows correct resource creation

terraform apply -auto-approve
# Success: Apply complete!
# Kind cluster created successfully
```

### 6. Verified Cluster Creation
```bash
kind get clusters
# sanjay-challenge

kubectl cluster-info --context kind-sanjay-challenge
# Kubernetes control plane is running at https://127.0.0.1:xxxxx
```

## Summary

All issues were successfully resolved:
- ✅ Terraform version constraint corrected to match installed version
- ✅ Provider version constraint updated to available 3.x range
- ✅ Variable names fixed to match actual configuration
- ✅ Line endings converted from Windows (CRLF) to Unix (LF) format
- ✅ Kind cluster successfully created and accessible via kubectl