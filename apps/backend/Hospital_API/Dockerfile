FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build

WORKDIR /build

COPY . .

RUN dotnet restore "Hospital_API.csproj"
RUN dotnet publish "Hospital_API.csproj" -c Release -o /app/publish

#############

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final

WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080

COPY --from=build /app/publish .

# Switch to built-in non-root user 'app' (UID 1654) provided by Microsoft's .NET images.
# This user already exists inside the base image — no need to create it manually.
USER app

EXPOSE 8080

CMD ["dotnet", "Hospital_API.dll"]

# docker rm -f cons-dotnet && docker rmi img-dotnet
# docker build . -t img-dotnet

# docker run -d -p 8080:8080 --name cons-dotnet img-dotnet
