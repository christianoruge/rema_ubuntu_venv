# Azure Container Apps Deployment Checklist

Use this checklist to ensure you have everything configured correctly before deploying to Azure.

## Prerequisites Checklist

- [ ] Azure account with active subscription
- [ ] Azure CLI installed (v2.50+)
- [ ] Docker installed and running
- [ ] Git installed
- [ ] Bash shell available
- [ ] Text editor for configuration files
- [ ] curl installed (for testing)

## Pre-Deployment Setup

### Local Testing
- [ ] Code review of `rema_pdf_to_excel.py`
- [ ] Test container locally: `docker-compose up`
- [ ] Test API endpoints with `./test_api.sh http://localhost:8000`
- [ ] Verify health check works: `curl http://localhost:8000/health`
- [ ] Test with sample PDF file

### Requirements verification
- [ ] All Python dependencies in `requirements.txt`
- [ ] Docker image builds successfully: `docker build -t rema-pdf-excel .`
- [ ] Image size reasonable (< 500 MB)
- [ ] No hardcoded credentials in code

## Azure Account Setup

- [ ] Azure subscription active and configured
- [ ] Logged in with Azure CLI: `az login`
- [ ] Correct subscription selected: `az account show`
- [ ] Sufficient quota in target region (Container Apps, ACR, Log Analytics)
- [ ] Permissions to create resources (Contributor role or equivalent)

## Resource Names Configuration

- [ ] Resource group name defined (e.g., `rema-resource-group`)
- [ ] Registry name defined and globally unique (e.g., `remapdfecr`)
- [ ] Container App name defined (e.g., `rema-pdf-excel`)
- [ ] Container App Environment name defined (e.g., `rema-env`)
- [ ] Region selected (e.g., `eastus`)
- [ ] All names follow Azure naming conventions

## Deployment Method Selection

Choose one of the following:

### Option A: Automated Script (Easiest)
- [ ] `deploy.sh` is executable: `chmod +x deploy.sh`
- [ ] Script permissions verified
- [ ] Environment variables reviewed
- [ ] Configuration values in script are correct

### Option B: Manual Azure CLI Commands
- [ ] Environment variables exported in shell
- [ ] Commands copy-pasted from `AZURE_SETUP.md`
- [ ] Each command tested before running next one

### Option C: Bicep Infrastructure as Code
- [ ] `main.bicep` reviewed and understood
- [ ] Parameters in `main.bicepparam` configured
- [ ] Bicep CLI available: `az bicep install`
- [ ] Template validated: `az bicep build --file main.bicep`

### Option D: GitHub Actions CI/CD
- [ ] GitHub repository created and pushed
- [ ] GitHub secrets configured (see [GitHub Actions Setup](#github-actions-setup-checklist))
- [ ] Workflow file `.github/workflows/deploy.yml` reviewed
- [ ] Personal access token created if needed

## Docker Image Preparation

- [ ] Dockerfile reviewed and customized if needed
- [ ] `.dockerignore` contains unnecessary files to exclude
- [ ] Image builds without errors: `docker build -t rema-pdf-excel .`
- [ ] Image runs successfully locally
- [ ] Health checks pass
- [ ] No security warnings in image

## Azure Container Registry Setup

- [ ] Registry created or verified to exist
- [ ] Permissions configured for authentication
- [ ] Admin account enabled (if using username/password)
- [ ] Image successfully pushed to ACR
- [ ] Image size and tags correct

Registry verification:
```bash
az acr repository list --name remapdfecr
```

## Container App Configuration

Environment Variables Verified:
- [ ] `CONTAINER_ENV=true` set
- [ ] `PORT=8000` matches exposed port
- [ ] `PYTHONUNBUFFERED=1` enabled for proper logging

Resource Settings Verified:
- [ ] CPU set to appropriate level (0.5-1.0 for typical use)
- [ ] Memory set to appropriate level (1.0-2.0 GB)
- [ ] Min replicas set (default: 1)
- [ ] Max replicas set (default: 3)
- [ ] Ingress configured (external, port 8000)
- [ ] Health checks configured

## Networking Configuration

- [ ] Ingress set to external (public)
- [ ] Port 8000 (or configured port) open
- [ ] HTTPS enabled (automatic with Azure)
- [ ] CORS configured if needed
- [ ] Firewall rules reviewed (if applicable)

## Monitoring & Logging Setup

- [ ] Log Analytics workspace created
- [ ] Container App Environment linked to Log Analytics
- [ ] Logging configured in Bicep/CLI
- [ ] Log browser accessible in Portal
- [ ] Alerts configured (optional)

Verify logs:
```bash
az containerapp logs show --name rema-pdf-excel --resource-group rema-resource-group
```

## Application Testing Checklist

### Immediate Post-Deployment (First 5 minutes)
- [ ] Container app status shows "Running"
- [ ] All replicas are ready
- [ ] Health check endpoint responds: `curl https://{app-url}/health`
- [ ] No errors in logs: `az containerapp logs show ...`

### API Testing
- [ ] Health endpoint works: `/health` returns `{"status": "healthy"}`
- [ ] Convert endpoint exists: `POST /convert`
- [ ] File upload works with test PDF
- [ ] Excel file is generated correctly
- [ ] Output file downloads successfully
- [ ] Error handling works (invalid file rejected)

Run automated tests:
```bash
./test_api.sh https://your-app-url
```

### Performance Testing
- [ ] Single PDF conversion completes in reasonable time
- [ ] Multiple concurrent requests handled
- [ ] Auto-scaling activates under load
- [ ] No memory leaks observed

## Security Verification

- [ ] Image security scanned before deployment
  ```bash
  trivy image your-registry.azurecr.io/rema-pdf-excel:latest
  ```
- [ ] No hardcoded secrets in image
- [ ] All credentials stored in Key Vault (optional for production)
- [ ] HTTPS enforced (automatic with Azure)
- [ ] WAF rules configured (optional)
- [ ] DDoS protection reviewed

## Cost Optimization

- [ ] Resource SKUs match requirements
  - [ ] ACR: Basic (sufficient for most)
  - [ ] Container Apps: Consumption plan selected
- [ ] Replicas configured for expected load
  - [ ] Low traffic: 1-2 replicas
  - [ ] Medium traffic: 2-3 replicas
  - [ ] High traffic: 3-5 replicas
- [ ] Scaling rules reviewed and realistic
- [ ] Reserved capacity considered (if predictable load)
- [ ] Cost estimation reviewed (typically $20-40/month)

## CI/CD Pipeline Setup (if using GitHub Actions)

### GitHub Secrets Configured
- [ ] `AZURE_CLIENT_ID` - Service principal App ID
- [ ] `AZURE_TENANT_ID` - Azure tenant ID
- [ ] `AZURE_SUBSCRIPTION_ID` - Azure subscription ID
- [ ] `ACR_USERNAME` - Registry username
- [ ] `ACR_PASSWORD` - Registry password
- [ ] `SLACK_WEBHOOK_URL` - (Optional) Slack notifications

### Workflow Configuration
- [ ] `.github/workflows/deploy.yml` exists and is valid
- [ ] Trigger events configured (push to main)
- [ ] Build step completes successfully
- [ ] Image scan step configured
- [ ] Push to ACR step successful
- [ ] Deployment step completes
- [ ] Health check step passes

Verify workflow:
```bash
# Push to main branch and monitor
git push origin main
# Then check GitHub Actions > Workflows
```

## Documentation Review

- [ ] README read and understood
- [ ] DEPLOYMENT.md reviewed
- [ ] AZURE_SETUP.md reviewed
- [ ] This checklist completed
- [ ] Team documentation updated
- [ ] Runbooks created for common issues
- [ ] Escalation path documented

## Post-Deployment

### First Week
- [ ] Monitor logs daily for errors
- [ ] Check resource usage (CPU, memory)
- [ ] Monitor auto-scaling behavior
- [ ] Review costs in Azure portal
- [ ] Gather team feedback
- [ ] Document any issues and resolutions

### Ongoing
- [ ] Monthly cost review
- [ ] Security updates applied
- [ ] Performance metrics reviewed
- [ ] Backup/disaster recovery tested
- [ ] Team training completed
- [ ] Documentation kept up-to-date

## Rollback Plan

- [ ] Previous image tagged and stored in ACR
- [ ] Rollback procedure documented
- [ ] Testing of rollback procedure completed

Rollback command (if needed):
```bash
az containerapp update \
  --name rema-pdf-excel \
  --resource-group rema-resource-group \
  --image {registry}/rema-pdf-excel:previous-version
```

## Common Issues & Resolution

### Container Won't Start
- [ ] Check environment variables (CONTAINER_ENV=true, PORT=8000)
- [ ] Check logs for startup errors
- [ ] Verify requirements.txt is complete
- [ ] Verify Dockerfile syntax

### Health Check Failing
- [ ] Ensure Flask app initializes properly
- [ ] Check /health endpoint is defined
- [ ] Verify port number matches
- [ ] Check network connectivity

### Image Push Failed
- [ ] Verify ACR credentials
- [ ] Check ACR still exists
- [ ] Verify sufficient storage quota
- [ ] Check network connectivity

### High Costs
- [ ] Review replicas usage
- [ ] Check for memory leaks
- [ ] Reduce max replicas if over-allocated
- [ ] Consider reserved instances

## Sign-Off

- [ ] Deployment lead: _____________________ Date: _______
- [ ] QA Testing: _____________________ Date: _______
- [ ] Team Lead: _____________________ Date: _______

---

**Notes:**
```
[Use this section to document deployment-specific details, issues encountered, and resolutions]
```

---

## Quick Reference Commands

```bash
# Authentication
az login

# View resources
az containerapp show --name rema-pdf-excel --resource-group rema-resource-group

# View logs
az containerapp logs show --name rema-pdf-excel --resource-group rema-resource-group --follow

# Update configuration
az containerapp update --name rema-pdf-excel --resource-group rema-resource-group --cpu 1.0 --memory 2.0Gi

# Restart container
az containerapp revision restart --name rema-pdf-excel --resource-group rema-resource-group --revision latest

# Delete resources
az group delete --name rema-resource-group --yes

# Test API
curl https://your-app-url/health
curl -X POST -F "file=@test.pdf" https://your-app-url/convert -o output.xlsx
```

## Helpful Links

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure CLI Reference](https://learn.microsoft.com/en-us/cli/azure/)
- [Bicep Template Reference](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Flask Documentation](https://flask.palletsprojects.com/)

---

**Last Updated:** 2024-01-XX
**Version:** 1.0
**Maintained By:** [Your Name/Team]
