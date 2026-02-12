param location string = resourceGroup().location
param containerAppName string = 'rema-pdf-excel'
param containerAppEnvName string = 'rema-env'
param containerRegistryName string = 'remapdfecr'
param containerImage string = 'rema-pdf-excel:latest'
param containerPort int = 8000
param cpuCores string = '0.5'
param memorySize string = '1.0'
param minReplicas int = 1
param maxReplicas int = 3
param registryServer string = ''
param registryUsername string = ''
param registryPassword string = ''

// Tags for resource organization
param tags object = {
  environment: 'production'
  application: 'rema-pdf-excel'
  team: 'development'
}

// Create Log Analytics Workspace for Container Apps
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${containerAppEnvName}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
  tags: tags
}

// Create Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-04-01-preview' = {
  name: containerAppEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
  tags: tags
}

// Create Container App
resource containerApp 'Microsoft.App/containerApps@2023-04-01-preview' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: containerPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      dapr: {
        enabled: false
      }
      maxInactiveRevisions: 10
      registries: empty(registryPassword) ? [] : [
        {
          server: registryServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: empty(registryPassword) ? [] : [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ]
    }
    template: {
      revisionSuffix: 'stable'
      containers: [
        {
          name: 'rema-pdf-excel'
          image: registryServer == '' ? containerImage : '${registryServer}/${containerImage}'
          resources: {
            cpu: json(cpuCores)
            memory: '${memorySize}Gi'
          }
          ports: [
            {
              containerPort: containerPort
              protocol: 'TCP'
            }
          ]
          env: [
            {
              name: 'CONTAINER_ENV'
              value: 'true'
            }
            {
              name: 'PORT'
              value: string(containerPort)
            }
            {
              name: 'PYTHONUNBUFFERED'
              value: '1'
            }
          ]
          probes: [
            {
              type: 'liveness'
              httpGet: {
                path: '/health'
                port: containerPort
                scheme: 'HTTP'
              }
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'readiness'
              httpGet: {
                path: '/health'
                port: containerPort
                scheme: 'HTTP'
              }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              initialDelaySeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            custom: {
              metric: 'rps'
              threshold: '1000'
            }
          }
          {
            name: 'cpu-scaling'
            custom: {
              metric: 'cpu'
              threshold: '70'
            }
          }
        ]
      }
    }
  }
  tags: tags
}

// Outputs
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output environmentId string = containerAppEnvironment.id
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output containerAppId string = containerApp.id
