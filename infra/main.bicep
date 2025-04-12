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
