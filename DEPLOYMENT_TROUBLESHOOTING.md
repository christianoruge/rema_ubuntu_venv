# Deployment Troubleshooting Guide

## Current Issue
You're seeing "Your functions 4.0 app is up and running" instead of your PDF converter web interface.

## Root Cause
Your previous deployment attempt **timed out** while creating the Container Apps Environment in **West Europe**. This left your resources in an incomplete state.

## Solution - Step by Step

### Step 1: Clean Up Failed Deployment
1. Go to [Azure Portal](https://portal.azure.com)
2. Search for "remaubuntuvenv" resource group
3. **Delete it completely** to remove all partial resources
4. Wait for deletion to complete (5-10 minutes)

### Step 2: Redeploy to a Different Region
The timeout suggests West Europe has capacity or connectivity issues. Try deploying to:
- **North Europe** (recommended - usually more stable)
- **UK South**
- **East US**

### Step 3: Deploy Using Azure CLI (More Reliable)

Instead of VS Code deployment, use Azure CLI directly:

```bash
# Login to Azure
az login

# Set your subscription (replace with your subscription ID)
az account set --subscription "a3c997dd-7073-4a9e-a5a8-09181df4ac0a"

# Create resource group in North Europe
az group create \
  --name remaubuntuvenv \
  --location northeurope

# Deploy the Bicep template
az deployment group create \
  --resource-group remaubuntuvenv \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### Step 4: Build and Push Container Image

Before deploying, you need to build your image and push it to Azure Container Registry:

```bash
# Login to your container registry
az acr login --name remapdfecr

# Build the image
az acr build --registry remapdfecr --image rema-pdf-excel:latest .

# After build completes, deploy with:
az deployment group create \
  --resource-group remaubuntuvenv \
  --template-file main.bicep \
  --parameters \
    registryServer=remapdfecr.azurecr.io \
    registryUsername=$(az acr credential show --resource-group remaubuntuvenv --name remapdfecr --query "username" -o tsv) \
    registryPassword=$(az acr credential show --resource-group remaubuntuvenv --name remapdfecr --query "passwords[0].value" -o tsv)
```

### Step 5: Verify Deployment

```bash
# Check container app status
az containerapp show \
  --resource-group remaubuntuvenv \
  --name rema-pdf-excel \
  --query "properties.configuration.ingress.fqdn"

# View logs
az containerapp logs show \
  --resource-group remaubuntuvenv \
  --name rema-pdf-excel \
  --follow
```

## Why This Happens

1. **Timeout in West Europe**: Network issues or region capacity constraints
2. **Wrong resource type**: Azure might create Functions App instead of Container App
3. **No startup command**: Docker runs but app doesn't start (we verified this is NOT your issue)
4. **Port mismatch**: App runs on different port than expected (we have port 8000 correctly configured)

## Key Configuration Files

- **Dockerfile**: ✅ Correct - starts Flask on port 8000
- **main.bicep**: ✅ Correct - creates Container Apps (not Functions)
- **rema_pdf_to_excel.py**: ✅ Correct - Flask app configured for container

## Common Issues After Redeployment

If you still see "Functions 4.0" message:
1. Check Azure Container Registry has the image built
2. Verify ingress is enabled in Bicep (`ingress: { external: true }`)
3. Check container logs for startup errors
4. Ensure PORT environment variable is set to 8000

## Your Current Credentials
- **Subscription ID**: a3c997dd-7073-4a9e-a5a8-09181df4ac0a
- **Registry Name**: remapdfecr
- **Container App Name**: rema-pdf-excel
- **Region to try**: northeurope (instead of westeurope)

---

**Need help?** Run: `az containerapp logs show --resource-group remaubuntuvenv --name rema-pdf-excel --follow`

This will show you real-time logs from your container and help diagnose any startup issues.
