using './main.bicep'

// Container App Configuration
param location = 'eastus'  // Change to your desired region
param containerAppName = 'rema-pdf-excel'
param containerAppEnvName = 'rema-env'
param containerRegistryName = 'remapdfecr'

// Use your ACR image or Docker Hub image
// For ACR: 'remapdfecr.azurecr.io/rema-pdf-excel:latest'
// For Docker Hub: 'your-username/rema-pdf-excel:latest'
param containerImage = 'rema-pdf-excel:latest'

param containerPort = 8000

// Resource sizing
param cpuCores = '0.5'      // 0.25, 0.5, 1.0
param memorySize = '1.0'    // in GB - must match valid combinations with CPU

// Scaling parameters
param minReplicas = 1
param maxReplicas = 3

// Registry credentials (only if using private ACR or Docker Hub)
// Leave empty for public images
param registryServer = ''           // e.g., 'remapdfecr.azurecr.io'
param registryUsername = ''
param registryPassword = ''

// Tags for resource organization
param tags = {
  environment: 'production'
  application: 'rema-pdf-excel'
  team: 'development'
  costCenter: 'operations'
}
