# Azure Container Apps Deployment Guide

This guide provides step-by-step instructions for deploying the REMA PDF to Excel converter to Azure Container Apps.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start (Automated)](#quick-start-automated)
3. [Manual Deployment](#manual-deployment)
4. [GitHub Actions Setup](#github-actions-setup)
5. [Scaling & Monitoring](#scaling--monitoring)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting, ensure you have:

- **Azure Account**: An active Azure subscription
- **Azure CLI**: Version 2.50+ installed
- **Docker**: For building images locally
- **Git**: For version control
- **Bash**: For running deployment scripts

### Install Required Tools

#### Azure CLI
```bash
# macOS
brew install azure-cli

# Linux (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows
choco install azure-cli
```

#### Docker
```bash
# Visit https://docs.docker.com/get-docker/
# And follow the instructions for your OS
```

## Quick Start (Automated)

### Step 1: Authenticate with Azure

```bash
az login
```

This opens your browser to authenticate with Azure.

### Step 2: Run the Deployment Script

```bash
chmod +x deploy.sh
./deploy.sh all
```

This script automatically:
- Creates resource group
- Creates Azure Container Registry (ACR)
- Builds Docker image
- Pushes to ACR
- Creates Container App Environment
- Deploys Container App

### Step 3: Get Your Application URL

The script displays the URL at the end. Save this for testing:

```
URL: https://rema-pdf-excel.xxxxx.eastus.azurecontainerinstances.io
```

## Manual Deployment

If you prefer step-by-step control, follow these instructions.

### Step 1: Set Environment Variables

```bash
export RESOURCE_GROUP="rema-resource-group"
export REGISTRY_NAME="remapdfecr"      # Must be globally unique and lowercase
export CONTAINER_APP_NAME="rema-pdf-excel"
export CONTAINER_APP_ENV="rema-env"
export LOCATION="eastus"               # Change as needed
```

### Step 2: Create Resource Group

```bash
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --tags environment=production application=rema-pdf-excel
```

### Step 3: Create Azure Container Registry

```bash
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $REGISTRY_NAME \
  --sku Basic \
  --admin-enabled true
```

Get the registry URL:
```bash
export REGISTRY_URL=$(az acr show \
  --name $REGISTRY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query loginServer -o tsv)

echo $REGISTRY_URL
```

### Step 4: Build and Push Docker Image

```bash
az acr build \
  --registry $REGISTRY_NAME \
  --image rema-pdf-excel:latest \
  .
```

### Step 5: Get Registry Credentials

```bash
export REGISTRY_USERNAME=$(az acr credential show \
  --name $REGISTRY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query username -o tsv)

export REGISTRY_PASSWORD=$(az acr credential show \
  --name $REGISTRY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "passwords[0].value" -o tsv)

echo "Username: $REGISTRY_USERNAME"
echo "Password: $REGISTRY_PASSWORD"
```

### Step 6: Create Container App Environment

```bash
az containerapp env create \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

### Step 7: Deploy Container App

```bash
az containerapp create \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APP_ENV \
  --image $REGISTRY_URL/rema-pdf-excel:latest \
  --target-port 8000 \
  --ingress 'external' \
  --registry-server $REGISTRY_URL \
  --registry-username $REGISTRY_USERNAME \
  --registry-password $REGISTRY_PASSWORD \
  --cpu 0.5 \
  --memory 1.0Gi \
  --environment-variables CONTAINER_ENV=true PORT=8000 PYTHONUNBUFFERED=1 \
  --min-replicas 1 \
  --max-replicas 3
```

### Step 8: Get Application URL

```bash
az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

## GitHub Actions Setup

For continuous deployment, set up GitHub Actions.

### Step 1: Configure Azure Credentials

Create GitHub Secrets with your Azure credentials:

```bash
# Get subscription ID
az account show --query id -o tsv

# Create service principal for GitHub
az ad sp create-for-rbac \
  --name "github-actions" \
  --role Contributor \
  --scopes "/subscriptions/{subscription-id}"
```

This returns:
```json
{
  "appId": "...",
  "displayName": "github-actions",
  "password": "...",
  "tenant": "..."
}
```

### Step 2: Add GitHub Secrets

Go to GitHub > Settings > Secrets and add:

- `AZURE_CLIENT_ID`: appId from above
- `AZURE_TENANT_ID`: tenant from above
- `AZURE_SUBSCRIPTION_ID`: subscription ID
- `ACR_USERNAME`: Registry username
- `ACR_PASSWORD`: Registry password
- `SLACK_WEBHOOK_URL`: (Optional) For Slack notifications

### Step 3: Customize Workflow

Edit `.github/workflows/deploy.yml` and update:

```yaml
env:
  REGISTRY_NAME: remapdfecr          # Your ACR name
  CONTAINER_APP_NAME: rema-pdf-excel # Your app name
  RESOURCE_GROUP: rema-resource-group # Your RG
  CONTAINER_APP_ENV: rema-env         # Your env name
```

### Step 4: Test Workflow

Push to main branch:

```bash
git push origin main
```

Check GitHub Actions > Workflows > Build and Deploy to Azure Container Apps

## Scaling & Monitoring

### View Logs

```bash
az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --follow
```

### Monitor Metrics

```bash
# CPU usage
az monitor metrics list \
  --resource "/subscriptions/{subscription-id}/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/containerApps/$CONTAINER_APP_NAME" \
  --metric "CpuUsageNanoCores" \
  --interval PT1M \
  --start-time 2024-01-01T00:00:00Z
```

### Scale the Application

```bash
# Update replicas
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 2 \
  --max-replicas 10
```

### Update Configuration

```bash
# Update image
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image $REGISTRY_URL/rema-pdf-excel:v2.0

# Update environment variables
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment-variables KEY=VALUE
```

## Testing the Deployment

### Health Check

```bash
FQDN=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "properties.configuration.ingress.fqdn" -o tsv)

curl https://$FQDN/health
# Response: {"status":"healthy"}
```

### Test PDF Conversion

```bash
# Using curl
curl -X POST -F "file=@test.pdf" \
  https://$FQDN/convert \
  -o output.xlsx

# Using Python
import requests

with open('test.pdf', 'rb') as f:
    response = requests.post(
        'https://app-url/convert',
        files={'file': f}
    )

with open('output.xlsx', 'wb') as f:
    f.write(response.content)
```

## Cost Optimization

### Consumption Plan Costs

Costs are based on:
- **vCPU-seconds**: $0.000011 per vCPU-second
- **Memory-seconds**: $0.000002 per GB-second
- **Requests**: Included in vCPU/Memory charges

### Cost Reduction Tips

1. **Use smaller resources for low traffic**
   ```bash
   az containerapp update \
     --name $CONTAINER_APP_NAME \
     --resource-group $RESOURCE_GROUP \
     --cpu 0.25 \
     --memory 0.5Gi
   ```

2. **Reduce max replicas for non-production**
   ```bash
   az containerapp update \
     --name $CONTAINER_APP_NAME \
     --resource-group $RESOURCE_GROUP \
     --max-replicas 2
   ```

3. **Use Basic tier ACR** (already configured)

4. **Enable auto-scaling** based on actual load

## Troubleshooting

### Container Won't Start

```bash
# Check logs
az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --follow

# Common issues:
# 1. Wrong PORT environment variable
# 2. Missing dependencies
# 3. File not found error
```

### Health Check Failing

```bash
# Check container status
az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP

# Look for revisionStatus: Failed
```

### Image Push Failed

```bash
# Check ACR credentials
az acr login --name $REGISTRY_NAME

# Try building again
az acr build \
  --registry $REGISTRY_NAME \
  --image rema-pdf-excel:latest \
  .
```

### High Memory Usage

```bash
# Get revision metrics
az containerapp revision list \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP

# Consider increasing memory allocation
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --memory 2.0Gi
```

## Cleanup

To delete all resources and stop being charged:

```bash
az group delete \
  --name $RESOURCE_GROUP \
  --yes
```

Or use the script:

```bash
./deploy.sh cleanup
```

## Additional Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Container Registry Documentation](https://learn.microsoft.com/en-us/azure/container-registry/)
- [Bicep Language Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure CLI Reference](https://learn.microsoft.com/en-us/cli/azure/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## Support

For issues or questions:
1. Check the logs with `az containerapp logs show`
2. Review the Troubleshooting section above
3. Check Azure Service Health status
4. Open an issue in the GitHub repository
