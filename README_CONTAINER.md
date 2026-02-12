# REMA PDF to Excel Converter - Container Deployment

A Flask-based PDF invoice parser that converts PDF files to formatted Excel spreadsheets, with support for both desktop and Azure Container Apps deployment.

## Features

✨ **Dual-Mode Application**
- Desktop mode with interactive GUI (tkinter)
- Container mode with REST API (Flask)

📊 **PDF Processing**
- Extracts invoice data from PDF files
- Parses structured receipt information
- Calculates VAT sums (25%, 15%, 0%)
- Generates formatted Excel spreadsheets

🚀 **Cloud Ready**
- Docker containerized
- Azure Container Apps compatible
- Auto-scaling capabilities
- Health check endpoints
- Continuous deployment via GitHub Actions

## Quick Start

### Local Development

```bash
# Set environment for local mode
export CONTAINER_ENV=false

# Run the application
python rema_pdf_to_excel.py
```

### Local Testing with Docker

```bash
# Build the image
docker build -t rema-pdf-excel:latest .

# Run the container
docker-compose up

# Or run directly
docker run -p 8000:8000 \
  -e CONTAINER_ENV=true \
  -v $(pwd)/pdf_input:/tmp/pdf_input \
  -v $(pwd)/output:/tmp/output \
  rema-pdf-excel:latest
```

### Test the API

```bash
# Health check
curl https://localhost:8000/health

# Convert PDF
curl -X POST -F "file=@invoice.pdf" \
  http://localhost:8000/convert \
  -o output.xlsx
```

## Files Structure

```
.
├── rema_pdf_to_excel.py          # Main application
├── requirements.txt              # Python dependencies
├── Dockerfile                    # Container image definition
├── docker-compose.yml            # Local development setup
├── .env.example                  # Environment variables template
├── .dockerignore                 # Docker build exclusions
├── .gitignore                    # Git exclusions
├── main.bicep                    # Azure IaC template
├── main.bicepparam              # Bicep parameters
├── deploy.sh                      # Automated deployment script
├── DEPLOYMENT.md                 # Detailed deployment guide
├── AZURE_SETUP.md               # Azure step-by-step guide
├── .github/workflows/deploy.yml  # CI/CD pipeline
└── README.md                     # This file
```

## Deployment Options

### Option 1: Quick Start with Script (Recommended)

```bash
chmod +x deploy.sh
./deploy.sh all
```

This automatically:
- Creates Azure resources
- Builds Docker image
- Pushes to Azure Container Registry
- Deploys to Container Apps

### Option 2: Manual Deployment

See [AZURE_SETUP.md](AZURE_SETUP.md) for step-by-step instructions.

### Option 3: Infrastructure as Code (Bicep)

```bash
az deployment group create \
  --resource-group my-rg \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### Option 4: GitHub Actions (CI/CD)

Set up GitHub Secrets and push to main branch. The workflow automatically:
- Builds Docker image
- Scans for vulnerabilities
- Pushes to ACR
- Deploys to Container Apps
- Runs health checks

## API Endpoints

### GET /health
Health check endpoint for monitoring and load balancing.

**Response:**
```json
{"status": "healthy"}
```

### POST /convert
Convert a PDF file to Excel format.

**Request:**
```bash
curl -X POST -F "file=@invoice.pdf" https://your-app-url/convert -o output.xlsx
```

**Parameters:**
- `file` (multipart/form-data): PDF file to convert

**Response:**
- Success (200): Binary Excel file
- Error (400): Invalid file or missing file
- Error (500): Processing error

**Example (Python):**
```python
import requests

with open('invoice.pdf', 'rb') as f:
    response = requests.post(
        'https://your-app-url/convert',
        files={'file': f}
    )
    
if response.status_code == 200:
    with open('output.xlsx', 'wb') as out:
        out.write(response.content)
    print("Conversion successful!")
else:
    print(f"Error: {response.json()}")
```

## Configuration

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CONTAINER_ENV` | `false` | Enable container mode |
| `PORT` | `8000` | Server port |
| `PYTHONUNBUFFERED` | `1` | Unbuffered Python output |

### Resource Sizing

Current configuration:
- **CPU**: 0.5 vCPU
- **Memory**: 1.0 GB
- **Min Replicas**: 1
- **Max Replicas**: 3

Can be adjusted based on load:

```bash
./deploy.sh deploy  # Then manually update resources
```

## Monitoring

### View Logs

```bash
export RESOURCE_GROUP="rema-resource-group"
export CONTAINER_APP_NAME="rema-pdf-excel"

az containerapp logs show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --follow
```

### Health Monitoring

The application includes:
- Liveness probe: Every 30 seconds
- Readiness probe: Every 10 seconds
- Automatic restart on failure

### Performance Metrics

```bash
# Monitor resource usage
watch -n 5 'az containerapp stats show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP'
```

## Scaling

### Manual Scaling

```bash
./deploy.sh deploy  # This uses the bicep parameters

# Or with Azure CLI
az containerapp update \
  --name rema-pdf-excel \
  --resource-group rema-resource-group \
  --min-replicas 2 \
  --max-replicas 5
```

### Auto-Scaling Rules

The application scales based on:
- CPU usage (threshold: 70%)
- Requests per second (threshold: 1000 RPS)

## Cost Estimation

Monthly costs for typical usage:

| Component | Estimated Cost |
|-----------|-----------------|
| Container Apps (1-3 replicas) | $10-30 |
| Container Registry | $5 |
| Log Analytics | $5 |
| **Total** | **$20-40** |

Prices in USD (East US region, as of 2024)

## Docker Image Details

### Base Image
- `python:3.12-slim` (optimized for size)

### Image Size
- ~400 MB (multi-stage build)

### Build Time
- ~2-3 minutes on first build
- ~30 seconds on subsequent builds (cached)

### Security
- Multi-stage build minimizes attack surface
- Slim base image reduces vulnerabilities
- No root user execution
- Health checks enabled

## Troubleshooting

### Container won't start

```bash
# Check logs
az containerapp logs show \
  --name rema-pdf-excel \
  --resource-group rema-resource-group \
  --follow

# Common issues:
# 1. Port mismatch - ensure PORT env var = container port
# 2. Missing dependencies - check requirements.txt
# 3. File permissions - ensure /tmp is writable
```

### PDF conversion fails

```bash
# Verify PDF format
curl -X POST -F "file=@test.pdf" \
  http://localhost:8000/convert \
  -v  # Verbose output shows errors
```

### Health check failing

```bash
# Test health endpoint directly
curl -v http://localhost:8000/health

# Check Flask app initialization
docker logs <container-id>
```

## Development

### Local Setup

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run in local mode
python rema_pdf_to_excel.py
```

### Testing Changes

```bash
# Rebuild Docker image
docker build -t rema-pdf-excel:dev .

# Test locally
docker-compose up
```

### Code Structure

- **Main Application**: `rema_pdf_to_excel.py`
  - PDF extraction and parsing
  - Data validation and transformation
  - Excel generation
  - Flask API endpoints

## Security Best Practices

1. **Image Security**
   - Scan with Trivy: `trivy image rema-pdf-excel:latest`
   - Keep base image updated
   - Multi-stage build reduces attack surface

2. **API Security**
   - Rate limiting (configure in production)
   - Input validation (PDF file check implemented)
   - HTTPS only (enforced by Azure)

3. **Data Security**
   - Temp files cleaned after processing
   - No sensitive data in logs
   - File upload limits enforced

## Performance Tips

1. **PDF Processing**
   - Keep PDFs under 100 MB
   - Ensure PDF structure matches expected format
   - Typical processing time: 1-2 seconds

2. **Scaling**
   - Auto-scales to 3 replicas by default
   - Adjust `maxReplicas` for expected load
   - Monitor CPU and memory usage

3. **Caching**
   - Docker layer caching enabled
   - ACR caching for faster deployments

## Documentation

- [AZURE_SETUP.md](AZURE_SETUP.md) - Comprehensive Azure deployment guide
- [DEPLOYMENT.md](DEPLOYMENT.md) - Detailed deployment instructions
- [main.bicep](main.bicep) - Infrastructure as Code template

## License

[Add your license here]

## Support

For issues or questions:
1. Check the [troubleshooting](AZURE_SETUP.md#troubleshooting) section
2. Review application logs: `./deploy.sh logs`
3. Open an issue on GitHub

## FAQ

**Q: Can I use this locally without Docker?**
A: Yes! Run with `CONTAINER_ENV=false` to use the desktop GUI mode.

**Q: How much does it cost to run on Azure?**
A: Typically $20-40 per month for development/testing. Production costs depend on load.

**Q: Can I use Docker Hub instead of ACR?**
A: Yes! Edit the deployment script and workflows to use Docker Hub credentials.

**Q: What's the maximum file size?**
A: Limited by available disk space in `/tmp` (typically 5-10 GB in Container Apps).

**Q: Can I add authentication?**
A: Yes, modify the Flask routes to add API key or OAuth authentication.

## Version History

- **1.0.0** (2024-01-XX) - Initial release with Azure Container Apps support

---

Happy deploying! 🚀
