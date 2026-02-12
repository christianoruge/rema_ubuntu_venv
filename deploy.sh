#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-rema-resource-group}"
REGISTRY_NAME="${REGISTRY_NAME:-remapdfecr}"
CONTAINER_APP_NAME="${CONTAINER_APP_NAME:-rema-pdf-excel}"
CONTAINER_APP_ENV="${CONTAINER_APP_ENV:-rema-env}"
LOCATION="${LOCATION:-eastus}"
IMAGE_NAME="rema-pdf-excel"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    log_success "All prerequisites are installed"
}

check_azure_login() {
    log_info "Checking Azure authentication..."
    
    if ! az account show &> /dev/null; then
        log_warning "Not authenticated with Azure. Running 'az login'..."
        az login
    fi
    
    SUBSCRIPTION=$(az account show --query id -o tsv)
    TENANT=$(az account show --query tenantId -o tsv)
    log_success "Authenticated to Azure (Subscription: $SUBSCRIPTION)"
}

create_resource_group() {
    log_info "Checking resource group: $RESOURCE_GROUP"
    
    if ! az group exists --name "$RESOURCE_GROUP" | grep -q true; then
        log_info "Creating resource group..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags environment=production application=rema-pdf-excel
        log_success "Resource group created"
    else
        log_success "Resource group already exists"
    fi
}

create_container_registry() {
    log_info "Checking Azure Container Registry: $REGISTRY_NAME"
    
    if ! az acr show --name "$REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Creating Azure Container Registry..."
        az acr create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$REGISTRY_NAME" \
            --sku Basic \
            --admin-enabled true
        log_success "Container registry created"
    else
        log_success "Container registry already exists"
    fi
}

build_and_push_image() {
    log_info "Building and pushing Docker image to ACR..."
    
    REGISTRY_URL=$(az acr show \
        --name "$REGISTRY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "loginServer" -o tsv)
    
    log_info "Registry URL: $REGISTRY_URL"
    
    # Build using ACR
    az acr build \
        --registry "$REGISTRY_NAME" \
        --image "${IMAGE_NAME}:latest" \
        --image "${IMAGE_NAME}:$(date +%s)" \
        .
    
    log_success "Image built and pushed successfully"
}

create_container_app_env() {
    log_info "Checking Container App Environment: $CONTAINER_APP_ENV"
    
    if ! az containerapp env show \
        --name "$CONTAINER_APP_ENV" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        
        log_info "Creating Container App Environment..."
        az containerapp env create \
            --name "$CONTAINER_APP_ENV" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION"
        
        log_success "Container App Environment created"
    else
        log_success "Container App Environment already exists"
    fi
}

deploy_container_app() {
    log_info "Deploying Container App: $CONTAINER_APP_NAME"
    
    REGISTRY_URL=$(az acr show \
        --name "$REGISTRY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "loginServer" -o tsv)
    
    REGISTRY_USERNAME=$(az acr credential show \
        --name "$REGISTRY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "username" -o tsv)
    
    REGISTRY_PASSWORD=$(az acr credential show \
        --name "$REGISTRY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "passwords[0].value" -o tsv)
    
    if az containerapp show \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        
        log_info "Updating existing Container App..."
        az containerapp update \
            --name "$CONTAINER_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --image "$REGISTRY_URL/$IMAGE_NAME:latest" \
            --registry-username "$REGISTRY_USERNAME" \
            --registry-password "$REGISTRY_PASSWORD"
        
    else
        log_info "Creating new Container App..."
        az containerapp create \
            --name "$CONTAINER_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --environment "$CONTAINER_APP_ENV" \
            --image "$REGISTRY_URL/$IMAGE_NAME:latest" \
            --target-port 8000 \
            --ingress 'external' \
            --registry-server "$REGISTRY_URL" \
            --registry-username "$REGISTRY_USERNAME" \
            --registry-password "$REGISTRY_PASSWORD" \
            --cpu 0.5 \
            --memory 1.0Gi \
            --environment-variables CONTAINER_ENV=true PORT=8000 PYTHONUNBUFFERED=1 \
            --min-replicas 1 \
            --max-replicas 3
    fi
    
    log_success "Container App deployed"
}

show_deployment_info() {
    log_info "Getting deployment information..."
    
    FQDN=$(az containerapp show \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.configuration.ingress.fqdn" -o tsv)
    
    APP_URL="https://$FQDN"
    
    echo ""
    echo -e "${GREEN}========== DEPLOYMENT SUCCESSFUL ==========${NC}"
    echo -e "Container App: ${BLUE}$CONTAINER_APP_NAME${NC}"
    echo -e "Resource Group: ${BLUE}$RESOURCE_GROUP${NC}"
    echo -e "URL: ${BLUE}${APP_URL}${NC}"
    echo -e "Health Check: ${BLUE}${APP_URL}/health${NC}"
    echo -e "Convert API: ${BLUE}${APP_URL}/convert${NC} (POST)"
    echo ""
    echo -e "Test with curl:"
    echo -e "  ${YELLOW}curl -X POST -F \"file=@your_file.pdf\" ${APP_URL}/convert -o output.xlsx${NC}"
    echo ""
}

cleanup() {
    log_info "Cleaning up..."
}

# Main execution
main() {
    log_info "Starting deployment process..."
    echo ""
    
    case "${1:-all}" in
        all)
            check_prerequisites
            check_azure_login
            create_resource_group
            create_container_registry
            build_and_push_image
            create_container_app_env
            deploy_container_app
            show_deployment_info
            ;;
        build)
            build_and_push_image
            ;;
        deploy)
            deploy_container_app
            show_deployment_info
            ;;
        info)
            show_deployment_info
            ;;
        cleanup)
            log_warning "Deleting resource group: $RESOURCE_GROUP"
            read -p "Are you sure? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                az group delete --name "$RESOURCE_GROUP" --yes
                log_success "Resource group deleted"
            fi
            ;;
        *)
            echo "Usage: $0 {all|build|deploy|info|cleanup}"
            echo ""
            echo "Commands:"
            echo "  all       - Full deployment (default)"
            echo "  build     - Build and push Docker image"
            echo "  deploy    - Deploy Container App"
            echo "  info      - Show deployment information"
            echo "  cleanup   - Delete all Azure resources"
            echo ""
            echo "Environment variables:"
            echo "  RESOURCE_GROUP     - Azure resource group (default: rema-resource-group)"
            echo "  REGISTRY_NAME      - ACR name (default: remapdfecr)"
            echo "  CONTAINER_APP_NAME - Container App name (default: rema-pdf-excel)"
            echo "  LOCATION           - Azure region (default: eastus)"
            exit 1
            ;;
    esac
    
    cleanup
}

# Run main function
trap cleanup EXIT
main "$@"
