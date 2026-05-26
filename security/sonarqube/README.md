# SonarQube Setup

![SonarQube](https://img.shields.io/badge/SonarQube-Code%20Quality-4E9BCD?logo=sonarqube&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Database-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%2FCD-2088FF?logo=githubactions&logoColor=white)
![.NET](https://img.shields.io/badge/.NET-Backend-512BD4?logo=dotnet&logoColor=white)
![React](https://img.shields.io/badge/React-Frontend-61DAFB?logo=react&logoColor=black)

SonarQube is used for static code analysis, maintainability checks, security hotspots, and CI quality gates.

## Architecture

```mermaid
flowchart LR
  gha[GitHub Actions] --> scanner[Sonar Scanner]
  scanner --> sq[SonarQube]
  sq --> pg[(PostgreSQL)]
  dev[Developer] --> ui[SonarQube UI]
  ui --> sq
  sq --> gate[Quality Gate]
  gate --> gha
```

## Runtime Model

| Component | Container | Purpose |
|---|---|---|
| SonarQube | `sonarqube` | Web UI, analysis API, quality gate engine. |
| PostgreSQL | `sonarqube-db` | Persistent SonarQube database. |
| GitHub Actions | `.github/workflows/cicd.yml` | Runs analysis and reads gate status. |

## Start

```bash
cd security
docker compose up -d sonarqube-db sonarqube
docker compose ps
```

Open:

```text
http://<host-ip-address>:9000
```

Default first login:

| Field | Value |
|---|---|
| Username | `admin` |
| Password | `admin` |

Change the password immediately after first login.

## Generate Token

Go to:

```text
Administration > Security > Users > Tokens
```

Create a token:

| Field | Value |
|---|---|
| Name | `sonar-token` |
| Type | User token |
| Expires | Choose a rotation period |

Store the generated token in GitHub Actions secrets or another secret manager.

## GitHub Actions Workflow

Add repository secrets:

```text
SONAR_HOST_URL=https://sonarqube.example.com
SONAR_TOKEN=<generated-sonarqube-token>
```

Workflow model:

```mermaid
sequenceDiagram
  participant GH as GitHub Actions
  participant API as ASP.NET API
  participant FE as React Frontend
  participant SQ as SonarQube

  GH->>API: dotnet restore/build
  GH->>SQ: dotnet-sonarscanner begin
  GH->>API: dotnet build with analysis
  GH->>SQ: dotnet-sonarscanner end
  GH->>FE: sonar-scanner frontend sources
  SQ-->>GH: quality gate result
```

Use secrets in workflow jobs:

```yaml
env:
  SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
  SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

Local placeholders:

```text
security/sonarqube/.env
```

## ASP.NET Core Analysis

Install scanner:

```bash
dotnet tool install --global dotnet-sonarscanner
```

Run from the repository root:

```bash
dotnet sonarscanner begin \
  /k:"hospital-api" \
  /d:sonar.host.url="$SONAR_HOST_URL" \
  /d:sonar.token="$SONAR_TOKEN"

dotnet build hospital_BE/Hospital_API/Hospital_API.csproj --configuration Release

dotnet sonarscanner end /d:sonar.token="$SONAR_TOKEN"
```

## React/Vite Analysis

```bash
sonar-scanner \
  -Dsonar.projectKey=hospital-frontend \
  -Dsonar.sources=hospital_FE/src \
  -Dsonar.exclusions=**/node_modules/**,**/dist/** \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.token="$SONAR_TOKEN"
```

Example properties file:

```text
security/sonarqube/sonar-project.frontend.properties.example
```

## Verify

```bash
docker compose ps sonarqube sonarqube-db
docker compose logs --tail=100 sonarqube
```

Check in the UI:

- project appears after first analysis
- quality gate status is computed
- issues and security hotspots are visible

## Security Checklist

- Keep SonarQube behind HTTPS before exposing it outside the server.
- Restrict inbound traffic to trusted IPs or self-hosted runners.
- Use one token per CI system.
- Rotate tokens regularly.
- Back up PostgreSQL and SonarQube data volumes before upgrades.
