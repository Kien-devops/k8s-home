# Hospital Backend Solution

![.NET](https://img.shields.io/badge/.NET-9-512BD4?logo=dotnet&logoColor=white)
![ASP.NET Core](https://img.shields.io/badge/ASP.NET%20Core-Web%20API-512BD4?logo=dotnet&logoColor=white)
![SQL Server](https://img.shields.io/badge/SQL%20Server-Database-CC2927?logo=microsoftsqlserver&logoColor=white)
![Entity Framework](https://img.shields.io/badge/Entity%20Framework%20Core-ORM-512BD4?logo=dotnet&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Image-2496ED?logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Runtime-326CE5?logo=kubernetes&logoColor=white)

This folder contains the backend solution for the Hospital platform. The main runtime project is `Hospital_API`, an ASP.NET Core 9 Web API backed by SQL Server and deployed as a container in Kubernetes.

## Architecture

```mermaid
flowchart TB
    client[Frontend or API client] --> api[Hospital_API<br/>ASP.NET Core 9]
    api --> controllers[Controllers<br/>api/[controller]]
    controllers --> services[Services]
    services --> repos[Repositories]
    repos --> ef[Entity Framework Core]
    ef --> sql[(SQL Server)]
    api --> jwt[JWT authentication]
    api --> sendgrid[SendGrid email service]
    api --> uploads[wwwroot/uploads]
```

## Folder Structure

| Path | Purpose |
|---|---|
| `Hospital_Project.sln` | Visual Studio solution file. |
| `Hospital_API/` | Main ASP.NET Core Web API project. |
| `nginx-deployment-guide.md` | Older manual deployment notes. |
| `temp_history/` | Historical snapshots, not part of runtime deployment. |

## Main Project

Read the detailed API documentation:

```text
hospital_BE/Hospital_API/README.md
```

## Local Build

```bash
cd hospital_BE/Hospital_API
dotnet restore
dotnet build
dotnet run
```

The API listens on the port configured by local launch settings during development. In Docker and Kubernetes, it listens on port `8080`.

## Local Configuration

Use a local ignored settings file:

```bash
cd hospital_BE/Hospital_API
cp appsettings.example.json appsettings.json
```

Set at least:

| Setting | Purpose |
|---|---|
| `ConnectionStrings:DefaultConnection` | SQL Server connection string. |
| `Jwt:Secret` | JWT signing secret. |
| `Jwt:Issuer` | Token issuer. |
| `Jwt:Audience` | Token audience. |
| `SendGrid:*` | Email delivery settings, if email features are used. |

Do not commit `appsettings.json`.

## Kubernetes Configuration

The Kubernetes deployment injects the database connection string through:

```text
ConnectionStrings__DefaultConnection
```

Create the secret:

```bash
cp k8s/secrets/default-connection.txt.example k8s/secrets/default-connection.txt
vi k8s/secrets/default-connection.txt

kubectl apply -f k8s/overlays/dev/namespace.yaml
kubectl -n hospital-dev create secret generic be-db-secret \
  --from-file=default-connection=k8s/secrets/default-connection.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

`k8s/secrets/default-connection.txt` is ignored by Git. Do not commit the real database host or password.

Restart after changing the secret:

```bash
kubectl -n hospital-dev rollout restart deployment/be-deployment-v1
kubectl -n hospital-dev rollout status deployment/be-deployment-v1
```

## Docker

```bash
cd hospital_BE/Hospital_API
docker build -t hospital-api .
docker run --rm -p 5247:8080 hospital-api
```

## Verification

Local or direct container:

```bash
curl -i http://localhost:5247/healthz
curl -i http://localhost:5247/swagger/v1/swagger.json
```

Public deployment through Traefik:

```bash
curl -i https://benhvien.teamdevops.shop/api/User/test
curl -i https://benhvien.teamdevops.shop/api/Branch
```

## Operational Notes

| Topic | Notes |
|---|---|
| Public API prefix | Kubernetes routes `/api/*` to the backend. |
| Health check | Backend exposes `/healthz`, used by Kubernetes probes. |
| Uploads | Kubernetes mounts an `emptyDir` volume for `/app/wwwroot/uploads`. |
| Database | SQL Server must be reachable from backend pods. |
| Swagger | Enabled in all environments by `Program.cs`; public routing depends on Gateway rules. |
