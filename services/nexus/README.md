# Nexus Repository Setup

![Nexus Repository](https://img.shields.io/badge/Nexus-Repository-1B1C30?logo=sonatype&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker&logoColor=white)
![NuGet](https://img.shields.io/badge/NuGet-.NET%20Packages-004880?logo=nuget&logoColor=white)
![npm](https://img.shields.io/badge/npm-JS%20Packages-CB3837?logo=npm&logoColor=white)
![Maven](https://img.shields.io/badge/Maven-Java%20Artifacts-C71A36?logo=apachemaven&logoColor=white)

Nexus is used as a private artifact repository and dependency proxy for CI/CD.

## Architecture

```mermaid
flowchart LR
  gha[GitHub Actions] --> nexus[Nexus Repository]
  be[ASP.NET Backend] --> nuget[NuGet repo/proxy]
  fe[React Frontend] --> npm[npm repo/proxy]
  java[Optional Java Service] --> maven[Maven releases/snapshots]
  nexus --> data[(nexus-data volume)]
  nexus --> nuget
  nexus --> npm
  nexus --> maven
```

## Repository Model

| Repository | Format | Purpose |
|---|---|---|
| `nuget-hosted` | NuGet | Internal .NET packages. |
| `nuget-group` | NuGet | Group hosted + proxy feeds. |
| `npm-hosted` | npm | Internal frontend packages. |
| `npm-group` | npm | Group hosted + proxy registries. |
| `maven-releases` | Maven | Release artifacts for Java services. |
| `maven-snapshots` | Maven | Snapshot artifacts for Java services. |
| `hospital-artifacts` | Raw | CI/CD build artifacts consumed by Docker image builds. |

## Start

```bash
cd security
docker compose up -d nexus
docker compose ps nexus
```

Open:

```text
http://<host-ip-address>:8081
```

## First Login

Get admin password:

```bash
docker exec -it nexus cat /nexus-data/admin.password
```

Login:

| Field | Value |
|---|---|
| Username | `admin` |
| Password | value from `/nexus-data/admin.password` |

Change the admin password immediately.

Local placeholders:

```text
security/nexus/.env
```

## Setup Workflow

```mermaid
sequenceDiagram
  participant Admin
  participant Nexus
  participant GH as GitHub Actions
  participant Consumer as Build Jobs

  Admin->>Nexus: create repositories
  Admin->>Nexus: create CI deploy user
  Admin->>Nexus: create read-only user
  GH->>Nexus: publish artifacts
  Consumer->>Nexus: restore packages
```

Recommended steps:

1. Disable anonymous access unless internal read-only access is required.
2. Create repository formats used by the project.
3. Create a CI deploy account.
4. Store Nexus credentials in GitHub Actions secrets.
5. Configure package managers to use Nexus group repositories.

For the current CI/CD workflow, create a raw hosted repository:

```text
Repository type: raw (hosted)
Name: hospital-artifacts
Deployment policy: Allow redeploy
```

The workflow uploads:

```text
hospital-artifacts/<branch>/backend-<commit-sha>.zip
hospital-artifacts/<branch>/frontend-<commit-sha>.zip
```

Then the EC2 build step downloads those files from Nexus and builds Docker images from the extracted artifacts.

The workflow also restores build dependencies through Nexus cache:

```text
dotnet restore -> nuget-group
npm ci         -> npm-group
```

Create or confirm these repositories:

```text
nuget-proxy  -> proxy to https://api.nuget.org/v3/index.json
nuget-group  -> group containing nuget-proxy and optional nuget-hosted
npm-proxy    -> proxy to https://registry.npmjs.org
npm-group    -> group containing npm-proxy and optional npm-hosted
```

## NuGet Example

Add source:

```bash
dotnet nuget add source https://nexus.example.com/repository/nuget-group/ \
  --name nexus-nuget \
  --username "$NEXUS_USERNAME" \
  --password "$NEXUS_PASSWORD" \
  --store-password-in-clear-text
```

Push package:

```bash
dotnet nuget push "*.nupkg" \
  --source https://nexus.example.com/repository/nuget-hosted/ \
  --api-key "$NEXUS_API_KEY"
```

## npm Example

```bash
npm config set registry https://nexus.example.com/repository/npm-group/
npm login --registry=https://nexus.example.com/repository/npm-hosted/
```

## Maven Example

For Java services, use:

```text
security/examples/nexus-maven-distribution-management.xml
```

Replace `https://nexus.example.com` with your Nexus domain.

## Verify

```bash
docker compose ps nexus
docker compose logs --tail=100 nexus
```

In the UI:

- create or confirm hosted/proxy/group repositories
- confirm CI user permissions
- test package restore from a CI runner

## Security Checklist

- Use HTTPS for all repository traffic.
- Keep anonymous access disabled unless explicitly needed.
- Use separate deploy and read-only accounts.
- Keep admin credentials out of CI jobs.
- Back up `nexus-data` before upgrades.
