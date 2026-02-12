# REMA PDF to Excel Converter - Container Deployment Guide

This application is a Flask-based PDF to Excel converter that extracts invoice data from PDF files and generates formatted Excel spreadsheets.

## Overview

The application supports two modes:
- **Local Mode**: Interactive GUI using tkinter for file selection (desktop)
- **Container Mode**: REST API with Flask for containerized deployment (Azure Container Apps)

## Prerequisites

- Docker installed locally (for local testing)
- Azure CLI installed (for Azure deployment)
- Azure subscription and resource group

## Local Testing with Docker

### 1. Build the Docker Image

```bash
docker build -t rema-pdf-excel:latest .
```

### 2. Run a Single Container

```bash
docker run -p 8000:8000 \
  -e CONTAINER_ENV=true \
  -e PORT=8000 \
  -v $(pwd)/pdf_input:/tmp/pdf_input \
  -v $(pwd)/output:/tmp/output \
  rema-pdf-excel:latest
```

The application will start and listen on `http://localhost:8000`

### 3. Using Docker Compose (Recommended for Local Testing)

```bash
docker-compose up --build
```

This will:
- Build the image
- Start the container
- Mount local directories for PDF input and output
- Enable health checks

To stop:
```bash
docker-compose down
```

## API Endpoints

### Health Check
```
GET /health
Response: {"status": "healthy"}
```

### Convert PDF to Excel
```
POST /convert
Content-Type: multipart/form-data

Field: file (binary) - PDF file to convert
Response: Excel file (application/vnd.openxmlformats-officedocument.spreadsheetml.sheet)
```

### Example Usage

```bash
# Using curl
curl -X POST -F "file=@your_file.pdf" http://localhost:8000/convert -o output.xlsx

# Using Python
import requests

with open('your_file.pdf', 'rb') as f:
    files = {'file': f}
    response = requests.post('http://localhost:8000/convert', files=files)
    
with open('output.xlsx', 'wb') as f:
    f.write(response.content)
```

## Deployment to Azure Container Apps

### Option 1: Using Azure Container Registry (ACR) and Azure CLI

#### 1. Create Azure Resources

```bash
# Set variables
export RESOURCE_GROUP="my-resource-group"
export REGISTRY_NAME="myregistry"
export CONTAINER_APP_NAME="rema-pdf-excel"
export LOCATION="eastus"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Azure Container Registry
az acr create --resource-group $RESOURCE_GROUP \
  --name $REGISTRY_NAME \
  --sku Basic \
  --admin-enabled true

# Build and push image to ACR
az acr build --registry $REGISTRY_NAME \
  --image rema-pdf-excel:latest \
  .
```

#### 2. Create Container Apps Environment

```bash
# Create environment
az containerapp env create \
  --name rema-env \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

#### 3. Deploy Container App

```bash
# Get ACR credentials
export REGISTRY_URL=$(az acr show --name $REGISTRY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "loginServer" -o tsv)
export REGISTRY_USERNAME=$(az acr credential show --name $REGISTRY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "username" -o tsv)
export REGISTRY_PASSWORD=$(az acr credential show --name $REGISTRY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "passwords[0].value" -o tsv)

# Create Container App
az containerapp create \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment rema-env \
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

#### 4. Get the Application URL

```bash
az containerapp show --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

### Option 2: Using Docker Hub

#### 1. Push to Docker Hub

```bash
# Build image
docker build -t your-dockerhub-username/rema-pdf-excel:latest .

# Login to Docker Hub
docker login

# Push image
docker push your-dockerhub-username/rema-pdf-excel:latest
```

#### 2. Deploy from Docker Hub

```bash
az containerapp create \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment rema-env \
  --image your-dockerhub-username/rema-pdf-excel:latest \
  --target-port 8000 \
  --ingress 'external' \
  --cpu 0.5 \
  --memory 1.0Gi \
  --environment-variables CONTAINER_ENV=true PORT=8000 PYTHONUNBUFFERED=1 \
  --min-replicas 1 \
  --max-replicas 3
```

## Environment Variables

- `CONTAINER_ENV=true` - Enables container mode (required for Azure)
- `PORT=8000` - Port to listen on (default 8000)
- `PYTHONUNBUFFERED=1` - Ensures Python output is logged immediately

## Resource Requirements

### Recommended for Azure Container Apps

- **CPU**: 0.5 - 1.0 vCPU
- **Memory**: 1.0 - 2.0 GB
- **Minimum Replicas**: 1
- **Maximum Replicas**: 3 (for auto-scaling)

### Performance Notes

- Typical PDF processing time: 1-2 seconds depending on file size
- Maximum recommended file size: 100 MB
- HTTP request timeout: Configure via Azure Load Balancing settings

## Monitoring and Logging

### View Logs in Azure

```bash
az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP
```

### Monitor Performance

```bash
az containerapp stats show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP
```

## Troubleshooting

### Container fails to start

1. Check logs:
```bash
az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP
```

2. Verify image is correct:
```bash
docker run -it rema-pdf-excel:latest bash
```

### Health check failing

The container includes a health check that verifies the Flask app is responding. If it fails:

1. Ensure PORT environment variable matches the container port (8000)
2. Check Flask app is initialized properly in container mode
3. Review logs for startup errors

### PDF conversion errors

1. Ensure PDF is readable and not corrupted
2. Verify PDF format matches expected structure
3. Check file permissions in /tmp directories

## Scaling Configuration

For production, adjust scaling policies:

```bash
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 2 \
  --max-replicas 5
```

The app auto-scales based on CPU and memory usage.

## Security Considerations

1. **Authentication**: Consider adding API key validation in production
2. **File Upload Limits**: Currently limited to file system space
3. **Temp Files**: Automatically cleaned in `/tmp` directory
4. **Network**: Use Azure Container App ingress controls for restricted access

## Cost Optimization

- Use `--max-replicas 1` for non-production environments
- Monitor actual usage and adjust CPU/memory accordingly
- Use Azure Container Registry with managed identities instead of username/password

## Clean Up Resources

To delete all Azure resources:

```bash
az group delete --name $RESOURCE_GROUP
```

## Support and Documentation

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

## File Processing Details

The application:
1. Accepts PDF files via POST request
2. Extracts invoice data using regular expressions
3. Generates Excel spreadsheets with formatted columns
4. Calculates VAT sums (25%, 15%, 0%)
5. Returns the Excel file for download

### Output Columns

- Dato (Date)
- Kvitteringsnr (Receipt Number)
- Ansvarlig (Responsible)
- EAN (Product Code)
- Varetekst (Product Description)
- Antall (Quantity)
- Nettopris (Net Price)
- Mva (VAT)
- Beløp i NOK (Amount in NOK)
- Sum 25% (VAT 25% Total)
- Sum 15% (VAT 15% Total)
- Sum 0% (VAT 0% Total)
