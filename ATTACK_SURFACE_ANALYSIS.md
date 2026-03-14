# Attack Surface Analysis - Selfhost Infrastructure

**Analysis Date**: March 8, 2026  
**Repository**: selfhost (your-username/selfhost)  
**Scope**: Web-exposed services and publicly accessible infrastructure

---

## Executive Summary

Your self-hosted infrastructure exposes **3 primary web services** through Traefik reverse proxy. The attack surface is **relatively well-controlled** with HTTPS enforcement, middleware protection, and proper network isolation. However, several security concerns and opportunities for hardening have been identified.

**Current Public Exposure:**
- ✅ **photos.example.com** (Immich photo library)
- ✅ **grafana.example.com** (Monitoring dashboard)
- ⚠️ **traefik.example.com** (Admin dashboard)

---

## 1. PRIMARY WEB-EXPOSED SERVICES

### A. Immich Photo Library (`photos.example.com`)

**Service**: `immich_server:2283`  
**Protocol**: HTTPS only (port 443)  
**Authentication**: Application-level (Immich's built-in auth)  
**TLS Configuration**: ✅ Strong (TLS 1.2+ with modern ciphers)

#### Potential Attack Vectors:

1. **Immich Application Vulnerabilities**
   - CVE exposure through outdated container images
   - Application logic flaws in photo sharing/permissions
   - File upload vulnerabilities (arbitrary file upload, XXS in metadata)
   - Database query injection (if Immich has SQLi vulnerabilities)
   
2. **Session/Authentication Bypasses**
   - Weak password enforcement (depends on Immich config)
   - Session fixation or hijacking
   - API token leakage

3. **Data Exfiltration**
   - Unauthenticated API endpoint exposure
   - Information disclosure through metadata
   - Backup file enumeration

4. **Resource Exhaustion**
   - Image processing DoS (uploading massive images)
   - Database connection pool exhaustion
   - No apparent rate limiting configured

#### Mitigation Status: ⚠️ PARTIAL
- TLS properly configured
- **MISSING**: Rate limiting middleware
- **MISSING**: WAF (Web Application Firewall)
- **MISSING**: API authentication documentation in code

---

### B. Grafana Monitoring Dashboard (`grafana.example.com`)

**Service**: `grafana:3000`  
**Protocol**: HTTPS only (port 443)  
**Authentication**: Default Grafana auth (username/password)  
**Default Credentials**: ⚠️ **RISK** - Using environment variables `GRAFANA_USER` and `GRAFANA_PASSWORD`

#### Exposed Data:

```yaml
# From docker-compose.yml
environment:
  GF_SECURITY_ADMIN_USER: ${GRAFANA_PASSWORD:-admin}
  GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-admin}
  # Defaults to "admin" if not set!
```

**What's Exposed**:
- System CPU, memory, disk usage metrics
- Container resource consumption
- Network I/O statistics
- System processes and load averages
- Potential to infer application behavior

#### Potential Attack Vectors:

1. **Information Disclosure**
   - System capacity and performance metrics reveal infrastructure details
   - Resource trends could expose planned scaling/growth
   - Combined with other reconnaissance = architecture mapping

2. **Credential Bruteforce**
   - Grafana has default port (3000) and known structure
   - No apparent rate limiting
   - Admin login at `/admin` is well-known endpoint

3. **Lateral Movement**
   - Dashboard could reveal internal service names/IPs
   - Prometheus targets might expose internal architecture
   - Could aid in internal network reconnaissance

4. **Data Integrity**
   - Grafana allows dashboard editing (if admin compromised)
   - Could modify alerting rules or thresholds
   - False metrics could cause operational mistakes

#### Mitigation Status: ⚠️ **HIGH RISK**
- **CRITICAL**: Default credentials with weak defaults
- **MISSING**: Rate limiting on login endpoint
- **MISSING**: Multi-factor authentication
- **MISSING**: IP whitelisting/allowlisting
- **MISSING**: Password policy enforcement

---

### C. Traefik Dashboard (`traefik.example.com`)

**Service**: `api@internal` (Traefik's built-in dashboard)  
**Protocol**: HTTPS only (port 443)  
**Authentication**: HTTP Basic Auth with middleware
**Credentials**: Hashed password in `.env`

```yaml
# From middlewares.yml
auth:
  basicAuth:
    users:
      - "admin:${TRAEFIK_PASSWORD}"
```

```bash
# From .env file
TRAEFIK_PASSWORD='$apr1$g57Z7kvO$21xJq4o8eQqLLjWidhKld0'
```

#### Exposed Information:

The Traefik dashboard reveals:
- **All configured routes** (host routing rules)
- **Service backend IPs/ports** (immich_server:2283, grafana:3000)
- **TLS configuration** (certificate details, resolvers)
- **Middleware chain** (auth, headers, etc.)
- **Real-time request metrics** (throughput, latency)
- **Error logs** (failed requests, rejections)

#### Potential Attack Vectors:

1. **Credential Compromise**
   - HTTP Basic Auth headers transmitted in Authorization header
   - Base64 decoded easily if HTTPS is bypassed
   - Credentials may be cached by browser
   - No HTTP-only or Secure cookie flags for basic auth

2. **Brute Force Attack**
   - No rate limiting on `/dashboard` endpoint
   - Basic auth doesn't have account lockout
   - Traefik doesn't implement exponential backoff

3. **Information Disclosure**
   - Backend service topology visible (immich_server, grafana)
   - Port mappings disclosed (2283, 3000)
   - Internal DNS names exposed
   - Routing rules show all public domains

4. **Configuration Tampering** (if compromised)
   - Could redirect traffic to attacker endpoints
   - Could disable TLS or authentication
   - Could modify routing rules
   - Could inject new routes to capture traffic

#### Mitigation Status: ⚠️ **MODERATE RISK**
- ✅ HTTPS enforced
- ✅ Basic authentication enabled
- ✅ Password hashed (not plaintext)
- **MISSING**: Rate limiting (brute force protection)
- **MISSING**: IP whitelisting
- **MISSING**: Multi-factor authentication
- **MISSING**: Audit logging
- **MISSING**: Read-only mode option
- **CONCERN**: Hashed password visible in git repo (even if readable)

---

## 2. INFRASTRUCTURE ATTACK SURFACE

### A. Network Layer (`main.tf`)

```terraform
ingress_security_rules {
  protocol    = "6" # TCP
  source      = "0.0.0.0/0"  # WORLD-OPEN
  tcp_options {
    min = 22
    max = 22
  }
}
```

**CRITICAL**: SSH (port 22) is open to the entire internet (0.0.0.0/0)

#### Potential Attack Vectors:

1. **SSH Brute Force**
   - Automated scanning for SSH on known ports
   - Dictionary attacks on common usernames (ubuntu, root, admin)
   - Credential stuffing from password dumps

2. **SSH Protocol Exploits**
   - CVEs in OpenSSH version
   - User enumeration attacks
   - Timing attacks

3. **Key Exposure**
   - If SSH key leaked, full server compromise
   - Key at: `var.ssh_public_key_path` (location not in repo)

#### Mitigation Status: ⚠️ **CRITICAL**
- **CRITICAL**: SSH world-open (0.0.0.0/0)
- **MISSING**: SSH key-based auth enforcement
- **MISSING**: Port knocking or single-packet authorization
- **MISSING**: Intrusion detection (fail2ban)
- **MISSING**: SSH config hardening (PermitRootLogin, PasswordAuth)
- **MISSING**: VPN/Bastion requirement

### B. Container Runtime

**Risk**: Docker socket mounted to Traefik container

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

- **Privilege**: Read-only access (somewhat mitigated)
- **Risk**: If Traefik compromised, attacker can:
  - List all containers and their configs
  - Access container secrets/env vars
  - Enumerate Docker volumes
  - Potentially escalate to write access

#### Mitigation Status: ⚠️ **MODERATE**
- ✅ Read-only socket access
- ✅ `no-new-privileges: true`
- **MISSING**: Docker API authentication
- **MISSING**: AppArmor/SELinux hardening

---

## 3. SECRETS & CREDENTIAL EXPOSURE

### Currently Exposed Credentials

#### a) **Traefik Admin Password** (Hashed, committed to repo)
```
File: /server/traefik/.env
TRAEFIK_PASSWORD='$apr1$g57Z7kvO$21xJq4o8eQqLLjWidhKld0'
```

- **Status**: Hashed (MD5-crypt)
- **Risk**: ⚠️ Hashes can be cracked (weak algorithm)
- **Recommendation**: Use more modern hashing (bcrypt, argon2)

#### b) **Email Address** (Public in repo)
```
ACME_EMAIL=user@example.com
DOMAIN=example.com
```

- **Status**: Discoverable
- **Risk**: Email enumeration for account takeover
- **Recommendation**: Use domain-based email alias

#### c) **Database Password** (In .env, not committed)
```
DB_PASSWORD=${DB_PASSWORD}  # Environment variable, not hardcoded ✅
```

- **Status**: ✅ Properly stored as environment variable
- **Risk**: Low (if server not compromised)

#### d) **B2/Rclone Credentials** (In scripts)
```bash
# /server/scripts/lib/rclone-env.sh
export RCLONE_CONFIG_BACKBLAZE_ACCOUNT="${B2_APPLICATION_KEY_ID}"
export RCLONE_CONFIG_BACKBLAZE_KEY="${B2_APPLICATION_KEY}"
```

- **Status**: Environment variables (good)
- **Risk**: ⚠️ If server compromised, full B2 bucket access lost
- **Recommendation**: Use B2 API tokens with limited scope

### Mitigation Status: ⚠️ **MODERATE**
- ✅ Secrets not hardcoded in repo
- ✅ Using environment variables
- **MISSING**: Secrets vault (HashiCorp Vault, Sealed Secrets, etc.)
- **MISSING**: Key rotation policy
- **MISSING**: Audit logging for secret access

---

## 4. HTTP/HTTPS CONFIGURATION

### TLS Configuration: ✅ **STRONG**

```yaml
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
        - TLS_AES_128_GCM_SHA256
        - TLS_AES_256_GCM_SHA384
        - TLS_CHACHA20_POLY1305_SHA256
```

- ✅ TLS 1.2 minimum
- ✅ Strong AEAD ciphers
- ✅ ECDHE for forward secrecy
- ✅ No weak/legacy ciphers

### Security Headers: ✅ **GOOD**

```yaml
security-headers:
  headers:
    frameDeny: true                    # X-Frame-Options: DENY
    sslRedirect: true                  # HSTS redirect
    browserXssFilter: true             # X-XSS-Protection
    contentTypeNosniff: true           # X-Content-Type-Options
    forceSTSHeader: true               # HSTS enabled
    stsIncludeSubdomains: true         # HSTS subdomains
    stsPreload: true                   # HSTS preload
    stsSeconds: 31536000               # HSTS 1 year
```

#### Status: ✅ **GOOD** BUT Missing Headers:

| Header | Current | Status |
|--------|---------|--------|
| X-Frame-Options | DENY | ✅ |
| HSTS | 1 year | ✅ |
| X-XSS-Protection | enabled | ⚠️ Deprecated |
| X-Content-Type-Options | nosniff | ✅ |
| Content-Security-Policy | **MISSING** | ❌ |
| X-Permitted-Cross-Domain-Policies | **MISSING** | ❌ |
| Referrer-Policy | **MISSING** | ❌ |
| Permissions-Policy | **MISSING** | ❌ |

### HTTP to HTTPS Redirect: ✅ **CONFIGURED**

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
```

- ✅ All HTTP traffic redirected to HTTPS

---

## 5. SERVICE-SPECIFIC VULNERABILITIES

### A. Immich

**Potential Issues**:
- ❌ No rate limiting configured
- ❌ No request size limits visible
- ⚠️ File upload endpoint is a common attack vector
- ⚠️ Database is PostgreSQL with vector extensions (pgvecto-rs) - unusual config

**Hardening**:
```yaml
# Add to middlewares.yml (RECOMMENDED)
http:
  middlewares:
    immich-ratelimit:
      rateLimit:
        average: 100
        period: 1m
        burst: 200
    immich-compress:
      compress: {}
```

### B. Grafana

**Potential Issues**:
- ❌ Admin credentials should be multi-factor
- ❌ No IP allowlisting
- ❌ Prometheus accessible internally without auth
- ⚠️ Node-exporter exposes system metrics on port 9100

**Exposed Endpoints**:
- `/grafana/api/datasources` (datasource list)
- `/grafana/api/search` (dashboard search)
- `/grafana/api/health` (health check)

---

## 6. AUTHENTICATION & AUTHORIZATION GAPS

| Service | Auth Type | MFA | IP Whitelist | Rate Limit |
|---------|-----------|-----|--------------|-----------|
| Immich | In-app | ❌ | ❌ | ❌ |
| Grafana | Basic Auth | ❌ | ❌ | ❌ |
| Traefik | Basic Auth | ❌ | ❌ | ❌ |

**Critical Gap**: **No centralized authentication system**
- No OAuth2/OIDC integration
- No LDAP/directory service
- No SSO capability
- No audit logging of who accessed what

---

## 7. LOGGING & MONITORING GAPS

### Current Logging:

```yaml
log:
  level: INFO
  format: common

accessLog:
  format: common
```

**Issues**:
- ❌ Logs stored locally (no central logging)
- ❌ No log rotation configured
- ❌ No intrusion detection (IDS/IPS)
- ❌ No SIEM integration
- ❌ Logs likely lost on container restart

**Missing**:
- Security event logging
- Failed authentication attempts
- Rate limit violations
- Suspicious request patterns

---

## 8. BACKUP & DATA PROTECTION

### Current Setup:
- ✅ Immich photos stored in Backblaze B2
- ✅ Database backups exist
- ⚠️ B2 credentials needed to restore

**Risks**:
- ❌ No encryption at rest in B2 (B2 provides, but not additional layer)
- ❌ No backup integrity verification visible
- ❌ Recovery time objective (RTO) not documented
- ❌ No disaster recovery testing documented

---

## SUMMARY: ATTACK SURFACE BY SEVERITY

### 🔴 CRITICAL (Immediate Action Required)

1. **SSH Port Open to Internet (0.0.0.0/0)**
   - **Impact**: Full server compromise
   - **Mitigation**: Restrict to VPN/bastion host only
   - **Effort**: Low

2. **Grafana Admin Credentials Default**
   - **Impact**: System monitoring access, potential pivot point
   - **Mitigation**: Enforce strong password, MFA, IP whitelist
   - **Effort**: Low

3. **No Rate Limiting on Admin Endpoints**
   - **Impact**: Brute force attacks possible
   - **Mitigation**: Add rate limit middleware
   - **Effort**: Low

### 🟡 HIGH (Should Fix Soon)

4. **Traefik Dashboard Credentials in Repository**
   - **Impact**: Git history searchable for credentials
   - **Mitigation**: Rotate password, use secrets manager
   - **Effort**: Medium

5. **Immich has no Input Validation Middleware**
   - **Impact**: Upload attacks, XXS, injection
   - **Mitigation**: Add WAF rules, rate limiting, size limits
   - **Effort**: Medium

6. **Prometheus/Metrics Exposed Internally**
   - **Impact**: Information disclosure if container compromised
   - **Mitigation**: Add authentication, restrict access
   - **Effort**: Low

### 🟠 MEDIUM (Fix When Possible)

7. **No Centralized Authentication**
   - **Impact**: Multiple credential systems to manage
   - **Mitigation**: Implement OAuth2/OIDC with Authelia
   - **Effort**: High

8. **Docker Socket Accessible to Traefik**
   - **Impact**: Lateral movement if Traefik compromised
   - **Mitigation**: Use docker-proxy or API auth
   - **Effort**: Medium

9. **No Audit Logging**
   - **Impact**: Cannot detect breach or suspicious activity
   - **Mitigation**: Implement centralized logging
   - **Effort**: High

10. **Backup Credentials in Server Memory**
    - **Impact**: Full B2 bucket compromise if server pwned
    - **Mitigation**: Use B2 restricted keys, rotate regularly
    - **Effort**: Medium

---

## RECOMMENDED SECURITY HARDENING

### Quick Wins (1-2 hours)

```bash
# 1. Restrict SSH to VPN only
# In infra/main.tf, change source to your VPN IP or use bastion

# 2. Add rate limiting to Traefik
# In traefik/dynamic/middlewares.yml:
#   rateLimit: {average: 10, period: 1m, burst: 20}

# 3. Force strong Grafana password
# Update .env with strong password, add environment variables:
#   GF_SECURITY_PASSWORD_VALIDATION_ENABLED=true
#   GF_SECURITY_PASSWORD_VALIDATION_WEAK=false

# 4. Disable Traefik API write mode
# In traefik.yml: --api.dashboard=true (read-only)
```

### Medium-Term (1-2 weeks)

- [ ] Implement Authelia for SSO/MFA
- [ ] Add WAF rules (ModSecurity or Cloudflare)
- [ ] Set up centralized logging (ELK stack or Loki)
- [ ] Implement secrets management (HashiCorp Vault or Sealed Secrets)
- [ ] Add rate limiting per service
- [ ] Enable audit logging

### Long-Term (1-3 months)

- [ ] Implement zero-trust architecture
- [ ] Network segmentation (separate pod networks per service)
- [ ] Regular vulnerability scanning (Trivy, Grype)
- [ ] Penetration testing
- [ ] Incident response plan
- [ ] Security training for operations team

---

## CONCLUSION

Your infrastructure is **reasonably secure** for a self-hosted setup but has **several critical gaps** that should be addressed:

1. ✅ **Good**: Strong TLS, HTTPS enforcement, no plaintext credentials in code
2. ⚠️ **Needs Work**: SSH open to internet, no rate limiting, weak authentication
3. ❌ **Missing**: Centralized authentication, audit logging, secrets management

**Next Step**: Start with SSH hardening and rate limiting - both are quick wins with high security impact.

---

## How to Use This Analysis

- **For Immediate Action**: Implement the "Quick Wins" section
- **For Risk Assessment**: Review the "By Severity" section
- **For Architecture Discussion**: Share the "Attack Surface" sections with your security team
- **For Compliance**: Map requirements to the recommendations

