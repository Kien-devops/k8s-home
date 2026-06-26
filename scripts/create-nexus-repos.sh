#!/usr/bin/env bash
# Script to automatically create NuGet, NPM, Raw, and Docker repositories in Nexus 3 via REST API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/nexus/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: ${ENV_FILE} not found. Please create it first."
  exit 1
fi

# Load variables
source "${ENV_FILE}"

NEXUS_URL="${NEXUS_URL%/}"
echo "Connecting to Nexus at: ${NEXUS_URL}"
echo "Using username: ${NEXUS_USERNAME}"

# Function to send POST request
create_repo() {
  local endpoint=$1
  local payload=$2
  local name
  name=$(echo "${payload}" | grep -oP '"name":\s*"\K[^"]+')

  echo "Creating repository: ${name}..."
  
  local status_code
  status_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" \
    -X POST "${NEXUS_URL}/service/rest/v1/repositories/${endpoint}" \
    -H "Content-Type: application/json" \
    -d "${payload}")

  if [ "${status_code}" -eq 201 ]; then
    echo "Successfully created ${name}."
  elif [ "${status_code}" -eq 400 ]; then
    echo "Repository ${name} already exists or invalid request configuration (HTTP 400)."
  else
    echo "Failed to create ${name}. HTTP Status: ${status_code}"
  fi
}

# 1. Create Raw Hosted Repository (hospital-artifacts)
create_repo "raw/hosted" '{
  "name": "hospital-artifacts",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  }
}'

# 2. Create NPM Hosted Repository (npm-hosted)
create_repo "npm/hosted" '{
  "name": "npm-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  }
}'

# 3. Create NPM Proxy Repository (npm-proxy)
create_repo "npm/proxy" '{
  "name": "npm-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://registry.npmjs.org/",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlockConfiguration": {
      "enabled": true,
      "blockedPeriod": 20
    }
  }
}'

# 4. Create NPM Group Repository (npm-group)
create_repo "npm/group" '{
  "name": "npm-group",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["npm-hosted", "npm-proxy"]
  }
}'

# 5. Create NuGet Hosted Repository (nuget-hosted)
create_repo "nuget/hosted" '{
  "name": "nuget-hosted",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  }
}'

# 6. Create NuGet Proxy Repository (nuget-proxy)
create_repo "nuget/proxy" '{
  "name": "nuget-proxy",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://api.nuget.org/v3/index.json",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  }
}'

# 7. Create NuGet Group Repository (nuget-group)
create_repo "nuget/group" '{
  "name": "nuget-group",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["nuget-hosted", "nuget-proxy"]
  }
}'

# 8. Create Docker Hosted Registry (hospital-docker on port 8082)
create_repo "docker/hosted" '{
  "name": "hospital-docker",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": 8082
  }
}'

echo "Nexus repository setup complete!"
