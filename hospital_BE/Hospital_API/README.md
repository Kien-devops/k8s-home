# Hospital API

![.NET](https://img.shields.io/badge/.NET-9-512BD4?logo=dotnet&logoColor=white)
![ASP.NET Core](https://img.shields.io/badge/ASP.NET%20Core-Web%20API-512BD4?logo=dotnet&logoColor=white)
![Entity Framework Core](https://img.shields.io/badge/EF%20Core-9-512BD4?logo=dotnet&logoColor=white)
![SQL Server](https://img.shields.io/badge/SQL%20Server-Database-CC2927?logo=microsoftsqlserver&logoColor=white)
![JWT](https://img.shields.io/badge/JWT-Authentication-000000?logo=jsonwebtokens&logoColor=white)
![Swagger](https://img.shields.io/badge/Swagger-OpenAPI-85EA2D?logo=swagger&logoColor=black)
![SendGrid](https://img.shields.io/badge/SendGrid-Email-1A82E2?logo=sendgrid&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Image-2496ED?logo=docker&logoColor=white)

`Hospital_API` is the ASP.NET Core 9 backend for the Hospital platform. It provides REST endpoints for users, roles, appointments, doctors, branches, medicines, inventory, invoices, payments, laboratory tests, medical records, blogs, uploads, authentication, and related hospital operations.

The API is deployed as a container behind Traefik and is reached publicly through the `/api` path prefix.

## Architecture

```mermaid
flowchart TB
    http[HTTP request<br/>/api/[controller]] --> middleware[ASP.NET Core middleware]
    middleware --> auth[JWT authentication<br/>token validation]
    auth --> controllers[Controllers]
    controllers --> services[Service layer]
    services --> repos[Repository layer]
    repos --> dbcontext[HospitalDbContext]
    dbcontext --> sql[(SQL Server)]
    services --> sendgrid[SendGrid email]
    controllers --> uploads[Static uploads<br/>wwwroot/uploads]
    middleware --> swagger[Swagger/OpenAPI]
```

## Tech Stack

| Area | Tool |
|---|---|
| Runtime | ASP.NET Core 9 |
| Database | SQL Server |
| ORM | Entity Framework Core 9 |
| Authentication | JWT Bearer |
| Password hashing | BCrypt.Net-Next |
| Mapping | AutoMapper |
| API documentation | Swagger / Swashbuckle |
| Email | SendGrid |
| Container runtime | .NET ASP.NET runtime image |

## Important Files and Folders

| Path | Purpose |
|---|---|
| `Program.cs` | Service registration, CORS, Swagger, JWT auth, EF Core, middleware, health endpoint. |
| `Data/HospitalDbContext.cs` | EF Core database context. |
| `Controllers/` | REST controllers using `api/[controller]`. |
| `Services/` | Business logic layer. |
| `Repositories/` | Data access layer. |
| `DTOs/` | Request and response models. |
| `Models/` | Domain/entity models. |
| `Migrations/` | EF Core migrations. |
| `Mapping/` | AutoMapper profiles. |
| `Filters/` | Swagger/file upload helpers. |
| `Templates/` | Email or document templates. |
| `wwwroot/uploads/` | Uploaded static files. |
| `appsettings.example.json` | Safe configuration template. |
| `appsettings.json` | Local ignored configuration file. |
| `Dockerfile` | Multi-stage build and runtime image. |

## Configuration

Create a local config file:

```bash
cp appsettings.example.json appsettings.json
```

Minimum local settings:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=<DB_HOST>,1433;Database=hospital;User Id=sa;Password=<DB_PASSWORD>;TrustServerCertificate=True;Encrypt=True"
  },
  "Jwt": {
    "Secret": "<long-random-secret>",
    "Issuer": "<issuer>",
    "Audience": "<audience>"
  },
  "SendGrid": {
    "ApiKey": "<sendgrid-api-key>",
    "SenderEmail": "<sender-email>",
    "SenderName": "Hospital"
  }
}
```

`appsettings.json` is ignored by Git. Use environment variables or Kubernetes Secrets for production values.

## Run Locally

```bash
dotnet restore
dotnet build
dotnet run
```

Common local checks:

```bash
curl -i http://localhost:<PORT>/healthz
curl -i http://localhost:<PORT>/swagger/v1/swagger.json
```

Replace `<PORT>` with the port printed by `dotnet run` or configured in launch settings.

## Database

The API uses Entity Framework Core with SQL Server.

Apply migrations when needed:

```bash
dotnet ef database update
```

If `dotnet ef` is not installed:

```bash
dotnet tool install --global dotnet-ef
```

Database-related endpoints such as `/api/Branch` and `/api/Doctor` require a working SQL Server connection. The lightweight `/api/User/test` endpoint is useful for checking routing without proving database connectivity.

For SQL Server TLS, use the exact keyword:

```text
TrustServerCertificate=True
```

Do not use misspelled variants such as `TrustServerCertifesicate`; `Microsoft.Data.SqlClient` will reject the connection string and database-backed endpoints will return `500`.

## Docker

Build:

```bash
docker build -t hospital-api .
```

Run:

```bash
docker run --rm -p 5247:8080 hospital-api
```

Check:

```bash
curl -i http://localhost:5247/healthz
```

## Kubernetes Deployment

The backend is deployed by:

```text
k8s/base/07-be-deployment.yaml
k8s/base/08-be-service.yaml
```

Runtime details:

| Setting | Value |
|---|---|
| Deployment | `be-deployment-v1` |
| Namespace | `hospital-prod` (or environment equivalent) |
| Replicas | `2` |
| Container port | `8080` |
| Service | `be-service-v1` |
| Image | `100.114.175.75:8082/hospital-be:<git-sha>` |
| Readiness probe | `GET /healthz` |
| Liveness probe | `GET /healthz` |
| DB env var | `ConnectionStrings__DefaultConnection` from `be-db-secret`. |

Create the database secret:

```bash
cp k8s/secrets/default-connection.txt.example k8s/secrets/default-connection.txt
vi k8s/secrets/default-connection.txt

kubectl apply -f k8s/overlays/prod/namespace.yaml
kubectl -n hospital-prod create secret generic be-db-secret \
  --from-file=default-connection=k8s/secrets/default-connection.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

`k8s/secrets/default-connection.txt` is ignored by Git. Do not commit the real database host or password.

Restart backend after secret changes:

```bash
kubectl -n hospital-prod rollout restart deployment/be-deployment-v1
kubectl -n hospital-prod rollout status deployment/be-deployment-v1
```

## Public API Tests

When deployed behind HAProxy and Traefik:

```bash
curl -i https://benhvien.teamdevops.shop/api/User/test
curl -i https://benhvien.teamdevops.shop/api/Branch
curl -i https://benhvien.teamdevops.shop/api/Doctor
```

`/api/User/test` validates routing to the backend. `/api/Branch` and `/api/Doctor` also validate SQL Server connectivity.

## Direct Cluster Debugging

Port-forward the service:

```bash
kubectl -n hospital-prod port-forward svc/be-service-v1 8080:80
```

Then check backend-only endpoints:

```bash
curl -i http://localhost:8080/healthz
curl -i http://localhost:8080/swagger/v1/swagger.json
```

Inspect logs:

```bash
kubectl -n hospital-prod logs deployment/be-deployment-v1 -c be-v1 --tail=100
```

Inspect environment injection:

```bash
kubectl -n hospital-prod get deploy be-deployment-v1 -o yaml | grep -A8 "ConnectionStrings__DefaultConnection"
```

Check the secret value:

```bash
kubectl -n hospital-prod get secret be-db-secret -o jsonpath='{.data.default-connection}' | base64 -d
echo
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `/healthz` fails in Kubernetes | Pod logs, container port `8080`, probe path. |
| `/api/User/test` fails publicly | HAProxy, Traefik route, backend service endpoints. |
| `/api/User/test` works but data endpoints fail | SQL connection string, SQL firewall, database credentials, migrations. |
| Log says `Keyword not supported: 'trustservercertifesicate'` | Fix the DB secret to use `TrustServerCertificate=True`, then restart `be-deployment-v1`. |
| JWT-protected endpoints return 401 | JWT issuer, audience, secret, token expiry, stored token revocation logic. |
| Uploads fail | `/app/wwwroot/uploads` volume permissions and init container logs. |
| Swagger URL wrong behind proxy | Forwarded headers, `X-Forwarded-Proto`, public route rules. |
