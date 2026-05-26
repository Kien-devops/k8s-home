# Security Hardening Checklist

## Network

- Allow SSH only from trusted IPs.
- Do not expose SonarQube or Nexus directly to the internet.
- Put a TLS reverse proxy or AWS ALB in front of the services.
- If using GitHub Actions, store SonarQube tokens in GitHub Secrets and restrict SonarQube access to trusted runners.

## Identity

- Change default admin passwords on first login.
- Use long, unique passwords.
- Store tokens in CI/CD secrets, never in Git.
- Use least-privilege service accounts for CI jobs.

## Docker

- Prefer Docker rootless mode for standalone utility servers.
- Keep Docker and host packages patched.
- Use named volumes for persistent data.
- Do not mount the host Docker socket into CI jobs unless absolutely required.

## SonarQube

- Use PostgreSQL for production-like setups.
- Generate a dedicated token per CI system.
- Enable quality gate checks in the pipeline.
- Rotate tokens periodically.

## Nexus

- Disable anonymous access unless explicitly required.
- Create separate hosted repositories for release and snapshot artifacts.
- Create read-only accounts for consumers and deploy accounts for CI.
- Back up `nexus-data` before upgrades.

## Trivy

- Fail CI on `CRITICAL` vulnerabilities.
- Keep DB updates enabled in CI.
- Scan container images and IaC files before deployment.
