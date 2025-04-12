#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Parameterize inputs
RESOURCE_GROUP=${1:-"aave-special-lever-rg"}
APP_NAME=${2:-"aave-special-lever-app"}
LOCATION=${3:-"centralus"}
REPO_URL=${4:-"https://github.com/Defi-Oracle-Tooling/Aave-Special-Lever"}
BRANCH=${5:-"main"}

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
  echo "❌ Azure CLI is not installed. Please install it and try again."
  exit 1
fi

# Create a log directory once at the beginning
LOG_DIR="deployment_logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/deployment_$TIMESTAMP.log"

# Log script start
echo "======== Deployment started at $(date) ========" | tee -a "$LOG_FILE"

# Simple existence check for Azure CLI functionality
if az --version &> /dev/null; then
  echo "✅ Azure CLI is installed and functioning" | tee -a "$LOG_FILE"
  # Log the version for informational purposes
  az --version | head -n 1 | tee -a "$LOG_FILE"
else
  echo "❌ Azure CLI is not functioning properly. Please check your installation." | tee -a "$LOG_FILE"
  exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
  echo "❌ You are not logged in to Azure. Please run 'az login' and try again." | tee -a "$LOG_FILE"
  exit 1
fi

# Check if Azure Developer CLI is installed
if ! command -v azd &> /dev/null; then
  echo "❌ Azure Developer CLI (azd) is not installed. Please install it and try again." | tee -a "$LOG_FILE"
  echo "Installation instructions: https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd" | tee -a "$LOG_FILE"
  exit 1
fi

# Function for error handling with logging
handle_error() {
  echo "❌ Error occurred at line $1. Check logs at $LOG_FILE for details." | tee -a "$LOG_FILE"
  exit 1
}

# Enable error trapping
trap 'handle_error $LINENO' ERR

# Check if Azure project exists and validate config format
echo "Checking if Azure project exists..." | tee -a "$LOG_FILE"
if [ -d ".azure" ] && [ -f ".azure/config" ]; then
  # Check if the config file has correct section headers
  if grep -q "^\[core\]" ".azure/config"; then
    echo "✅ Azure project configuration found and format is valid." | tee -a "$LOG_FILE"
    PROJECT_EXISTS=true
  else
    echo "⚠️ Azure project configuration found but format is invalid. Backing up and recreating..." | tee -a "$LOG_FILE"
    # Backup the existing config
    BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    cp ".azure/config" ".azure/config.backup.$BACKUP_TIMESTAMP"
    
    # Extract values from the existing config if possible
    EXISTING_NAME=$(grep "^name = " ".azure/config" | cut -d'=' -f2 | xargs)
    EXISTING_SUB=$(grep "^subscription = " ".azure/config" | cut -d'=' -f2 | xargs)
    EXISTING_LOC=$(grep "^location = " ".azure/config" | cut -d'=' -f2 | xargs)
    EXISTING_RG=$(grep "^resource_group = " ".azure/config" | cut -d'=' -f2 | xargs)
    EXISTING_ENV=$(grep "^environment = " ".azure/config" | cut -d'=' -f2 | xargs)
    
    # Use extracted values or defaults
    APP_NAME=${EXISTING_NAME:-$APP_NAME}
    LOCATION=${EXISTING_LOC:-$LOCATION}
    RESOURCE_GROUP=${EXISTING_RG:-$RESOURCE_GROUP}
    ENV_NAME=${EXISTING_ENV:-"$APP_NAME-env"}
    
    # Create properly formatted config file with section headers
    cat > ".azure/config" << EOF
[core]
name = $APP_NAME
subscription = ${EXISTING_SUB:-$(az account show --query id -o tsv 2>/dev/null || echo "")}
location = $LOCATION
resource_group = $RESOURCE_GROUP
environment = $ENV_NAME
EOF
    echo "✅ Azure project configuration fixed with proper format." | tee -a "$LOG_FILE"
    PROJECT_EXISTS=true
  fi
else
  echo "ℹ️ No existing Azure project configuration found. Need to initialize." | tee -a "$LOG_FILE"
  PROJECT_EXISTS=false
fi

# Initialize Azure Developer CLI if project doesn't exist
if [ "$PROJECT_EXISTS" = false ]; then
  echo "Initializing Azure project manually..." | tee -a "$LOG_FILE"
  
  # Create necessary directories
  mkdir -p .azure
  mkdir -p infra
  mkdir -p .github/workflows
  
  # Create properly formatted Azure config file with section headers
  # Following Azure best practices for configuration management
  cat > .azure/config << EOF
[core]
name = $APP_NAME
subscription = $(az account show --query id -o tsv)
location = $LOCATION
resource_group = $RESOURCE_GROUP
environment = $APP_NAME-env
EOF

  # Create an azd yaml config file for additional settings
  cat > .azure/azd.yaml << EOF
# Azure Developer CLI Configuration File
# See https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/azd-schema
name: $APP_NAME
services:
  web:
    project: .
    host: staticwebapp
    language: html
EOF

  echo "✅ Azure configuration created manually." | tee -a "$LOG_FILE"
  
  # Add static web app infrastructure manually
  echo "Setting up Static Web App infrastructure..." | tee -a "$LOG_FILE"
  
  # Create infra directory if it doesn't exist
  mkdir -p infra
  
  # Add a retry mechanism for resiliency
  # This function implements exponential backoff for transient failures
  function retry_with_backoff {
    local max_attempts=3
    local timeout=1
    local attempt=1
    local exit_code=0

    while [[ $attempt -le $max_attempts ]]; do
      echo "Attempt $attempt of $max_attempts: $@" | tee -a "$LOG_FILE"
      "$@"
      exit_code=$?

      if [[ $exit_code -eq 0 ]]; then
        break
      fi

      echo "Command failed with exit code $exit_code. Retrying in $timeout seconds..." | tee -a "$LOG_FILE"
      sleep $timeout
      attempt=$((attempt + 1))
      timeout=$((timeout * 2))
    done

    if [[ $exit_code -ne 0 ]]; then
      echo "Command '$@' failed after $max_attempts attempts" | tee -a "$LOG_FILE"
    fi

    return $exit_code
  }
  
  # Create a simple Bicep file for Static Web App - following Azure best practices for IaC
  cat > infra/main.bicep << 'EOF'
@description('The name of the static web app')
param name string = 'staticwebapp-${uniqueString(resourceGroup().id)}'

@description('Location for the static web app')
param location string = resourceGroup().location

@description('SKU for the static web app')
param sku string = 'Free'

@description('Tags for resource organization')
param tags object = {
  Environment: 'Development'
  Application: 'Aave-Special-Lever'
  DeployedDate: utcNow('yyyy-MM-dd')
}

resource staticWebApp 'Microsoft.Web/staticSites@2022-03-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
  }
}

output staticWebAppName string = staticWebApp.name
output staticWebAppUrl string = staticWebApp.properties.defaultHostname
EOF

  echo "Created Bicep infrastructure file" | tee -a "$LOG_FILE"

  # Set up azd hooks for deployment
  mkdir -p .azure/staticwebapp

  # Create a default app service configuration for the static web app
  echo "Setting up Static Web App deployment..." | tee -a "$LOG_FILE"

  # Verify the project was actually initialized
  if [ -d ".azure" ] && [ -f ".azure/config" ]; then
    echo "✅ Azure project successfully initialized." | tee -a "$LOG_FILE"
    PROJECT_EXISTS=true
  else
    echo "❌ Azure project initialization failed - .azure directory not created." | tee -a "$LOG_FILE"
    exit 1
  fi
else
  echo "Using existing Azure project configuration." | tee -a "$LOG_FILE"
fi

# Add a retry mechanism for resiliency (if not defined already)
if ! type retry_with_backoff > /dev/null 2>&1; then
  function retry_with_backoff {
    local max_attempts=3
    local timeout=1
    local attempt=1
    local exit_code=0

    while [[ $attempt -le $max_attempts ]]; do
      echo "Attempt $attempt of $max_attempts: $@" | tee -a "$LOG_FILE"
      "$@"
      exit_code=$?

      if [[ $exit_code -eq 0 ]]; then
        break
      fi

      echo "Command failed with exit code $exit_code. Retrying in $timeout seconds..." | tee -a "$LOG_FILE"
      sleep $timeout
      attempt=$((attempt + 1))
      timeout=$((timeout * 2))
    done

    if [[ $exit_code -ne 0 ]]; then
      echo "Command '$@' failed after $max_attempts attempts" | tee -a "$LOG_FILE"
    fi

    return $exit_code
  }
fi
cleanup_on_failure() {
  local exit_code=$1
  local stage=$2
  
  echo "⚠️ Deployment failed during $stage stage with exit code $exit_code" | tee -a "$LOG_FILE"
  echo "🧹 Performing cleanup of partially created resources..." | tee -a "$LOG_FILE"
  
  # Ask user if they want to clean up resources
  read -p "Do you want to clean up any partially created resources? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing resource group $RESOURCE_GROUP if it exists..." | tee -a "$LOG_FILE"
    if az group exists --name $RESOURCE_GROUP; then
      retry_with_backoff az group delete --name $RESOURCE_GROUP --yes --no-wait
      echo "✅ Resource cleanup initiated. The resource group will be deleted in the background." | tee -a "$LOG_FILE"
    else
      echo "✅ No resources to clean up. Resource group doesn't exist." | tee -a "$LOG_FILE"
    fi
  else
    echo "⚠️ Skipping cleanup. Partially created resources may still exist." | tee -a "$LOG_FILE"
  fi
  
  exit $exit_code
}

# Enhanced validation before deployment
echo "Running comprehensive deployment validation..." | tee -a "$LOG_FILE"
if [ "$PROJECT_EXISTS" = true ]; then
  # Create the resource group first to avoid validation errors
  echo "Creating resource group if it doesn't exist..." | tee -a "$LOG_FILE"
  if ! az group exists --name $RESOURCE_GROUP &>/dev/null; then
    if ! az group create --name $RESOURCE_GROUP --location $LOCATION --tags Environment=Development Application=$APP_NAME "DeployedDate=$(date +"%Y-%m-%d")" 2>&1 | tee -a "$LOG_FILE"; then
      echo "❌ Failed to create resource group." | tee -a "$LOG_FILE"
      cleanup_on_failure 1 "Resource group creation"
    fi
    echo "✅ Resource group created: $RESOURCE_GROUP" | tee -a "$LOG_FILE"
  else
    echo "Resource group $RESOURCE_GROUP already exists." | tee -a "$LOG_FILE"
  fi
  
  # Validate the Bicep file first using ARM validation
  echo "Validating Bicep template..." | tee -a "$LOG_FILE"
  if ! az bicep build --file infra/main.bicep 2>&1 | tee -a "$LOG_FILE"; then
    echo "❌ Bicep template validation failed." | tee -a "$LOG_FILE"
    cleanup_on_failure 1 "Bicep validation"
  fi
  
  # Try direct ARM template deployment validation as a more reliable alternative to azd
  echo "Validating ARM template deployment..." | tee -a "$LOG_FILE"
  if ! az deployment group validate --resource-group $RESOURCE_GROUP --template-file infra/main.bicep 2>&1 | tee -a "$LOG_FILE"; then
    echo "❌ ARM template validation failed." | tee -a "$LOG_FILE"
    cleanup_on_failure 1 "ARM template validation"
  fi
  
  echo "✅ Bicep template validation passed." | tee -a "$LOG_FILE"
else
  echo "❌ Cannot validate deployment - project initialization failed." | tee -a "$LOG_FILE"
  exit 1
fi

# Ask user to confirm deployment with more detailed information
echo
echo "🔍 Deployment Information:"
echo "  - Resource Group: $RESOURCE_GROUP"
echo "  - Location: $LOCATION"
echo "  - Application Name: $APP_NAME"
echo "  - Log File: $LOG_FILE"
echo
read -p "Do you want to proceed with the deployment? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled by user." | tee -a "$LOG_FILE"
  exit 0
fi

# Set deployment start time for metrics
DEPLOY_START_TIME=$(date +%s)

# Provision resources - directly use the ARM template deployment instead of azd
echo "Provisioning resources..." | tee -a "$LOG_FILE"
PROVISION_SUCCESS=false

# First try with standard azd command with retries
if retry_with_backoff azd provision 2>&1 | tee -a "$LOG_FILE"; then
  PROVISION_SUCCESS=true
else
  echo "⚠️ azd provision failed, falling back to direct ARM template deployment..." | tee -a "$LOG_FILE"
  
  # Deploy the ARM template directly as a fallback
  if az deployment group create --resource-group $RESOURCE_GROUP --template-file infra/main.bicep --query properties.provisioningState -o tsv 2>&1 | tee -a "$LOG_FILE" | grep -q "Succeeded"; then
    PROVISION_SUCCESS=true
    echo "✅ ARM template deployment succeeded." | tee -a "$LOG_FILE"
  else
    echo "❌ ARM template deployment failed." | tee -a "$LOG_FILE"
    cleanup_on_failure 1 "Resource provisioning"
  fi
fi

# Only continue if resources were successfully provisioned
if [ "$PROVISION_SUCCESS" = true ]; then
  # Calculate deployment duration
  DEPLOY_END_TIME=$(date +%s)
  DEPLOY_DURATION=$((DEPLOY_END_TIME - DEPLOY_START_TIME))
  echo "✅ Resources provisioned successfully in $DEPLOY_DURATION seconds." | tee -a "$LOG_FILE"
else
  echo "❌ Resource provisioning failed but error handling didn't catch it." | tee -a "$LOG_FILE"
  exit 1
fi

# After provisioning, add tags to the resource group via Azure CLI
echo "Adding tags to resource group for better management..." | tee -a "$LOG_FILE"
if ! az group update --name $RESOURCE_GROUP --tags Environment=Development Application=$APP_NAME "DeployedDate=$(date +"%Y-%m-%d")" 2>&1 | tee -a "$LOG_FILE"; then
  echo "⚠️ Warning: Failed to add tags to resource group. Continuing with deployment." | tee -a "$LOG_FILE"
fi

# Deploy the app
echo "Deploying the app..."
if ! azd deploy 2>&1 | tee -a "$LOG_FILE"; then
  echo "❌ Failed to deploy the app. Check logs at $LOG_FILE for details."
  exit 1
fi

# Calculate total deployment time
TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$((TOTAL_END_TIME - DEPLOY_START_TIME))

echo "✅ Deployment completed successfully!"
echo "📝 Logs available at: $LOG_FILE"

# Create comprehensive deployment summary with detailed resource information
echo "📊 Deployment Summary:"
echo "════════════════════════════════════════════════════════════════"
echo "GENERAL INFORMATION"
echo "────────────────────────────────────────────────────────────────"
echo "🔹 Application Name: $APP_NAME"
echo "🔹 Resource Group: $RESOURCE_GROUP"
echo "🔹 Location: $LOCATION"
echo "🔹 Deployment Duration: $TOTAL_DURATION seconds"
echo "🔹 Deployment Timestamp: $(date)"

# Get Static Web App details
echo
echo "STATIC WEB APP DETAILS"
echo "────────────────────────────────────────────────────────────────"
# More reliable approach to get webapp details
echo "Retrieving Static Web App details..." | tee -a "$LOG_FILE"

# First try to get the latest deployment name rather than assuming "main"
DEPLOYMENT_NAME=$(az deployment group list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv 2>/dev/null || echo "")

if [ -z "$DEPLOYMENT_NAME" ]; then
  echo "🔸 No deployment found in resource group $RESOURCE_GROUP" | tee -a "$LOG_FILE"
  # Try to get web app directly by listing resources
  WEBAPP_NAME=$(az staticwebapp list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv 2>/dev/null || echo "")
else
  echo "🔹 Found deployment: $DEPLOYMENT_NAME" | tee -a "$LOG_FILE"
  # Extract the webapp name from deployment outputs
  WEBAPP_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name $DEPLOYMENT_NAME --query "properties.outputs.staticWebAppName.value" -o tsv 2>/dev/null || echo "")
fi

# If we have a web app name, get more details
if [ -n "$WEBAPP_NAME" ]; then
  echo "🔹 Static Web App Name: $WEBAPP_NAME" | tee -a "$LOG_FILE"
  
  # Get the Static Web App details directly using its name
  WEBAPP_DETAILS=$(az staticwebapp show --name $WEBAPP_NAME --resource-group $RESOURCE_GROUP -o json 2>/dev/null || echo "")
  
  if [ -n "$WEBAPP_DETAILS" ]; then
    # Parse details safely using jq if available, otherwise use grep
    if command -v jq &> /dev/null; then
      WEBAPP_URL=$(echo $WEBAPP_DETAILS | jq -r '.defaultHostname // ""')
      WEBAPP_SKU=$(echo $WEBAPP_DETAILS | jq -r '.sku.name // "Free"')
    else
      WEBAPP_URL=$(echo $WEBAPP_DETAILS | grep -o '"defaultHostname":"[^"]*' | sed 's/"defaultHostname":"//g' || echo "")
      WEBAPP_SKU=$(echo $WEBAPP_DETAILS | grep -o '"name":"[^"]*' | head -1 | sed 's/"name":"//g' || echo "Free")
    fi
    
    if [ -n "$WEBAPP_URL" ]; then
      echo "🔹 Application URL: https://$WEBAPP_URL" | tee -a "$LOG_FILE"
    else
      echo "🔸 Application URL: Not available yet" | tee -a "$LOG_FILE"
    fi
    
    echo "🔹 SKU: ${WEBAPP_SKU:-Free}" | tee -a "$LOG_FILE"
    echo "🔹 Content Location: public/" | tee -a "$LOG_FILE"
  else
    echo "🔸 Could not retrieve Static Web App details" | tee -a "$LOG_FILE"
    echo "🔹 SKU: Free (default)" | tee -a "$LOG_FILE"
    echo "🔹 Content Location: public/" | tee -a "$LOG_FILE"
  fi
else
  echo "🔸 Static Web App not found or still provisioning" | tee -a "$LOG_FILE"
  echo "🔹 Check the Azure portal for details: https://portal.azure.com/#blade/HubsExtension/BrowseResourceGroups" | tee -a "$LOG_FILE"
fi

# Check for the GitHub Actions workflow for CI/CD
echo
echo "CI/CD CONFIGURATION"
echo "────────────────────────────────────────────────────────────────"
if [ -d ".github/workflows" ] && [ "$(ls -A .github/workflows)" ]; then
  echo "🔹 CI/CD: GitHub Actions workflow(s) configured"
  echo "🔹 Workflow Location: .github/workflows/"
else
  echo "🔹 CI/CD: No automated deployment workflows configured"
  echo "🔹 Manual Deployment: Use 'azd deploy' to update the application"
fi

# Resource tags information
echo
echo "RESOURCE TAGGING"
echo "────────────────────────────────────────────────────────────────"
echo "🔹 Environment: Development"
echo "🔹 Application: $APP_NAME"
echo "🔹 Deployed Date: $(date +"%Y-%m-%d")"

# Costs and optimization
echo
echo "COST INFORMATION"
echo "────────────────────────────────────────────────────────────────"
echo "🔹 Static Web App SKU: Free"
echo "🔹 Free Tier Limits: 100GB bandwidth/month, 2 custom domains, 500K API requests/day"
echo "🔹 Estimated Cost: $0.00/month (Free tier)"

# Next steps
echo
echo "NEXT STEPS"
echo "────────────────────────────────────────────────────────────────"
echo "🔹 Configure custom domain: az staticwebapp hostname add --name $WEBAPP_NAME --hostname your-domain.com"
echo "🔹 Set up authentication: az staticwebapp auth update --name $WEBAPP_NAME"
echo "🔹 Monitor your app: az monitor metrics list --resource $WEBAPP_NAME"
echo "════════════════════════════════════════════════════════════════"

# Also output azd environment values for reference
echo
echo "AZURE DEVELOPER CLI ENVIRONMENT VALUES:"
azd env get-values
