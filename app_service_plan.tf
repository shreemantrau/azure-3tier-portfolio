resource "azurerm_service_plan" "main" {
  name = "asp-3tier"
  resource_group_name = azurerm_resource_group.main.name
  location = azurerm_resource_group.main.location
  os_type = "Linux"
  sku_name = "B1"
}


resource "azurerm_linux_web_app" "web" {
  name = "app-3tier-web"
  location = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id = azurerm_service_plan.main.id
  
  //managed identity below enables the app services to communicate with PaaS without storing credentials
  //azure takes care of the credentials and authorization for us
  
  identity{
    type = "SystemAssigned"
  }
  site_config {
  }

}

resource "azurerm_linux_web_app" "app" {
  name = "app-3tier-app"
  location = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id = azurerm_service_plan.main.id
  
  //App Services natievely supports special syntax that tells it to go fetch this value from Key Vault rahter than relying on terraform
  // versionless_id = secret URL without a specific version pinned - always resolves to latest.
  // Using plain "id" would lock App Service to this exact version forever, even after rotation.
  app_settings = {
    //"SQL_PASSWORD" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.sql_password.versionless_id})"
    "SQL_PASSWORD" = "@Microsoft.KeyVault(SecretUri=https://kv-3tier-shreyas.vault.azure.net/secrets/sql-admin-password/)"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    # App Insights auto-generates connection_string when created - not something we define
    # ourselves. Referencing it here tells this App Service exactly where to send its
    # telemetry (requests, response times, errors) once App Insights integration is active.
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
  }


  //managed identity below enables the app services to communicate with PaaS without storing credentials
  //azure takes care of the credentials and authorization for us
  identity {
    type = "SystemAssigned"
  }
  
  site_config {
    app_command_line = "gunicorn --bind=0.0.0.0 app:app"
  }

  lifecycle {
    ignore_changes = [virtual_network_subnet_id]
  }
}

# Gives the "app" App Service actual network presence INSIDE the VNet.
# Without this, App Service's outbound traffic never enters the VNet at all -
# it tries to reach SQL Server publicly, which fails since SQL denies public access.
# This is what lets App Service reach SQL's private endpoint instead.
resource "azurerm_app_service_virtual_network_swift_connection" "app" {
  app_service_id = azurerm_linux_web_app.app.id
  subnet_id      = azurerm_subnet.app.id
}

