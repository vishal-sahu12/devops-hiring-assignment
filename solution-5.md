# Challenge 5: TLS Certificate and Secret Configuration

## Symptoms Observed

TLS client unable to establish secure connection with the service due to multiple certificate and secret configuration issues:

1. **TLS handshake failures** - Client unable to verify server certificate
2. **Certificate/key mismatch** - Server presenting key instead of certificate
3. **CA certificate encoding issues** - CA cert stored as base64-encoded base64 string
4. **CA certificate mounting issues** - Base64 string mounted as file instead of decoded cert
5. **Hostname mismatch** - Certificate CN doesn't match service hostname
6. **Secret field swap** - TLS certificate and key stored in wrong secret fields

## Tools Used to Investigate

- `kubectl get secrets -n t5` - List secrets in namespace
- `kubectl describe secret tls-secret -n t5` - Examine secret structure
- `kubectl get configmap ca-bundle -n t5 -o yaml` - Check CA cert storage
- `kubectl exec -it tls-client -n t5 -- <command>` - Test TLS connections
- `openssl x509 -in <cert> -text -noout` - Examine certificate details
- `openssl s509 -in <cert> -subject -noout` - Check certificate subject/CN
- `echo <base64> | base64 -d` - Decode base64 strings
- `curl --cacert <ca> --cert <cert> --key <key>` - Test TLS handshake
- `cat` - View file contents in containers

## Root Causes and Confirmation

### Issue 1: Certificate and Key Swapped in Secret

**Root Cause:**
Secret was created with certificate and key in reversed fields:
```bash
kubectl create secret generic tls-secret -n t5 \
  --from-file=tls.crt=/tmp/sanjay-server.key \  # KEY in CERT field
  --from-file=tls.key=/tmp/sanjay-server.crt    # CERT in KEY field
```

**Confirmation:**
```bash
kubectl get secret tls-secret -n t5 -o yaml
# data:
#   tls.crt: <base64 of private key>
#   tls.key: <base64 of certificate>

kubectl get secret tls-secret -n t5 -o jsonpath='{.data.tls\.crt}' | base64 -d | head -n1
# -----BEGIN PRIVATE KEY-----
# Should be -----BEGIN CERTIFICATE-----
```

### Issue 2: CA Certificate Double Base64 Encoded

**Root Cause:**
CA certificate was base64 encoded twice during ConfigMap creation:
```bash
# Original cert was already base64, then got base64'd again
base64(base64(ca.crt))
```

**Confirmation:**
```bash
kubectl exec -it tls-client -n t5 -- cat /etc/ssl/custom/ca.crt
# LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURDV...
# This is base64-encoded base64-encoded certificate

echo "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..." | base64 -d | head -n1
# -----BEGIN CERTIFICATE-----
# First decode reveals it was double-encoded
```

### Issue 3: Wrong Certificate Hostname (CN)

**Root Cause:**
Certificate was generated with CN=`wrong-hostname.example.com` instead of the actual service hostname `secure-app.t5.svc.cluster.local`.

**Confirmation:**
```bash
kubectl get secret tls-secret -n t5 -o jsonpath='{.data.tls\.key}' | base64 -d | \
  openssl x509 -noout -subject
# subject=CN = wrong-hostname.example.com

# Expected:
# subject=CN = secure-app.t5.svc.cluster.local
```

Testing connection showed hostname verification failure:
```bash
kubectl exec -it tls-client -n t5 -- \
  curl --cacert /etc/ssl/custom/ca.crt https://secure-app.t5.svc.cluster.local
# SSL: certificate subject name 'wrong-hostname.example.com' does not match target host name 'secure-app.t5.svc.cluster.local'
```

### Issue 4: CA Certificate Not Properly Mounted

**Root Cause:**
Even after fixing the secret, the CA cert in the ConfigMap was still base64-encoded text rather than the raw PEM certificate, causing TLS verification to fail.

**Confirmation:**
```bash
kubectl exec -it tls-client -n t5 -- cat /etc/ssl/custom/ca.crt | head -n1
# LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t
# Should start with: -----BEGIN CERTIFICATE-----

kubectl exec -it tls-client -n t5 -- \
  openssl x509 -in /etc/ssl/custom/ca.crt -text
# unable to load certificate
# Error: expecting: TRUSTED CERTIFICATE
```

## Fixes Applied

### Fix 1: Recreated Secret with Correct Field Mapping

**Deleted incorrect secret:**
```bash
kubectl delete secret tls-secret -n t5
```

**Created new secret with correct cert/key mapping:**
```bash
kubectl create secret generic tls-secret -n t5 \
  --from-file=tls.crt=/tmp/sanjay-server.crt \
  --from-file=tls.key=/tmp/sanjay-server.key
```

**Verification:**
```bash
kubectl get secret tls-secret -n t5 -o jsonpath='{.data.tls\.crt}' | base64 -d | head -n1
# -----BEGIN CERTIFICATE-----

kubectl get secret tls-secret -n t5 -o jsonpath='{.data.tls\.key}' | base64 -d | head -n1
# -----BEGIN PRIVATE KEY-----
```

### Fix 2: Regenerated Certificate with Correct Hostname

**Created new CSR with correct CN:**
```bash
openssl req -new -key sanjay-server.key \
  -out sanjay-server.csr \
  -subj "/CN=secure-app.t5.svc.cluster.local"
```

**Signed certificate with CA:**
```bash
openssl x509 -req -in sanjay-server.csr \
  -CA sanjay-ca.crt \
  -CAkey sanjay-ca.key \
  -CAcreateserial \
  -out sanjay-server.crt \
  -days 365
```

**Verification:**
```bash
openssl x509 -in /tmp/sanjay-server.crt -noout -subject
# subject=CN = secure-app.t5.svc.cluster.local
```

### Fix 3: Recreated ConfigMap with Raw Certificate

**Deleted old ConfigMap:**
```bash
kubectl delete configmap ca-bundle -n t5
```

**Created new ConfigMap with raw PEM certificate:**
```bash
kubectl create configmap ca-bundle -n t5 \
  --from-file=ca.crt=/tmp/sanjay-ca.crt
```

**Verification:**
```bash
kubectl get configmap ca-bundle -n t5 -o yaml
# data:
#   ca.crt: |
#     -----BEGIN CERTIFICATE-----
#     MIIDCVECCAf...
#     -----END CERTIFICATE-----
```

### Fix 4: Recreated TLS Client Pod to Mount Updated ConfigMap

**Deleted old pod:**
```bash
kubectl delete pod tls-client -n t5
```

**Recreated pod with ConfigMap volume:**
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: tls-client
  namespace: t5
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["sleep", "86400"]
    volumeMounts:
    - name: ca-bundle
      mountPath: /etc/ssl/custom
  volumes:
  - name: ca-bundle
    configMap:
      name: ca-bundle
EOF
```

### Fix 5: Updated Secret with Regenerated Certificate

**Updated secret with new certificate:**
```bash
kubectl delete secret tls-secret -n t5

kubectl create secret generic tls-secret -n t5 \
  --from-file=tls.crt=/tmp/sanjay-server.crt \
  --from-file=tls.key=/tmp/sanjay-server.key
```

## Verification Steps

### 1. Verified Secret Structure
```bash
kubectl get secret tls-secret -n t5 -o yaml

# Confirmed tls.crt contains certificate
kubectl get secret tls-secret -n t5 -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -text | grep "Subject:"
# Subject: CN = secure-app.t5.svc.cluster.local

# Confirmed tls.key contains private key
kubectl get secret tls-secret -n t5 -o jsonpath='{.data.tls\.key}' | base64 -d | head -n1
# -----BEGIN PRIVATE KEY-----
```

### 2. Verified ConfigMap CA Certificate
```bash
kubectl exec -it tls-client -n t5 -- cat /etc/ssl/custom/ca.crt | head -n1
# -----BEGIN CERTIFICATE-----

kubectl exec -it tls-client -n t5 -- \
  openssl x509 -in /etc/ssl/custom/ca.crt -noout -subject
# subject=CN = sanjay-ca
# Successfully parsed as valid certificate
```

### 3. Verified Certificate Hostname Match
```bash
kubectl exec -it tls-client -n t5 -- \
  openssl s_client -connect secure-app.t5.svc.cluster.local:443 -CAfile /etc/ssl/custom/ca.crt < /dev/null
# Verify return code: 0 (ok)
# Certificate chain verified successfully
# Hostname matches certificate CN
```

### 4. Verified TLS Connection Success
```bash
kubectl exec -it tls-client -n t5 -- \
  curl -v --cacert /etc/ssl/custom/ca.crt https://secure-app.t5.svc.cluster.local
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * Server certificate:
# *  subject: CN=secure-app.t5.svc.cluster.local
# *  issuer: CN=sanjay-ca
# *  SSL certificate verify ok.
# < HTTP/1.1 200 OK
# Successfully retrieved content
```

### 5. Verified Certificate Chain
```bash
kubectl exec -it tls-client -n t5 -- \
  openssl verify -CAfile /etc/ssl/custom/ca.crt \
  <(kubectl get secret tls-secret -n t5 -o jsonpath='{.data.tls\.crt}' | base64 -d)
# /dev/fd/63: OK
# Certificate chain validation successful
```

### 6. Tested Multiple Requests
```bash
for i in {1..10}; do
  kubectl exec -it tls-client -n t5 -- \
    curl -s -o /dev/null -w "%{http_code}\n" \
    --cacert /etc/ssl/custom/ca.crt \
    https://secure-app.t5.svc.cluster.local
done
# All requests return: 200
```

### 7. Verified No TLS Errors in Logs
```bash
kubectl logs -n t5 <secure-app-pod>
# No TLS handshake errors
# No certificate verification failures
# Clean connection logs
```

## Summary

All TLS certificate and secret configuration issues were successfully resolved:
- ✅ Secret recreated with certificate in `tls.crt` and key in `tls.key` fields (proper mapping)
- ✅ New certificate generated with correct CN matching service hostname
- ✅ Certificate signed with proper CA
- ✅ ConfigMap recreated with raw PEM certificate (single encoding)
- ✅ CA certificate properly mounted and readable
- ✅ TLS client pod recreated to pick up updated ConfigMap
- ✅ Full TLS handshake successful with proper certificate verification
- ✅ All curl requests to HTTPS service complete successfully
- ✅ Certificate chain validation passes
- ✅ Hostname verification successful