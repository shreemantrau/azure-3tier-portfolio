/*
Creating keyvault below.
-public netwrok access is set to false to ensure its private
-enable_rbac_auth is used to make sure App Service Plans systemAssigned idenity gets
  authorized for communicaiton

RESOURCE creates a resource while DATA is used to extract information just like get request
*/

resource "azurerm_key_vault" "main" {
  name = "kv-3tier-shreyas"
  location = azurerm_resource_group.main.location
  sku_name = "standard"
  resource_group_name = azurerm_resource_group.main.name 
  tenant_id = data.azurerm_client_config.currently.tenant_id
  public_network_access_enabled = false // this was set to true becasue keyvault did not allow connection from public internet to write data in keyvault. Other solutons include VPN and bastion 
  enable_rbac_authorization = true
}

data "azurerm_client_config" "currently" {}

resource "azurerm_private_endpoint" "keyvault" {
  name = "pe-keyvault"
  location = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id = azurerm_subnet.keyvault.id

  private_service_connection {
    name = "psc_keyvault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names = ["vault"]
    is_manual_connection = false
  }
}

resource "azurerm_private_dns_zone" "keyvault" {
  name = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name = "keyvault-dns-link"
  resource_group_name = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id = azurerm_virtual_network.main.id
}

resource "azurerm_private_dns_a_record" "keyvault" {
  name = azurerm_key_vault.main.name
  zone_name = azurerm_private_dns_zone.keyvault.name
  resource_group_name = azurerm_resource_group.main.name
  ttl = 300
  //this stores the IP address of the the Endpoint which is nothing but the KeyVault in this case
  records = [azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address]
}

/*
Blocks below are required to make sure managed identity in the service plan has the autorization to access keyvault
there are two solutions for this

Older Way - Where we literally give access to the idenity ... line 71 - 74
          - Access Policies are specific to Key Vault different resources will have different ways to grant access
New Preferred Way - We set RBAC ... line #81 this the acutal role (Provides Read onlu) in AZ typo would make terraform throw an error
                  - With RBAC all resources will have the RBAC just like we did on line 81 ... keeping it consistent 
                    thorught the project
*/

//older way of doing it
/*
resource "azurerm_key_vault_access_policy" "app" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id = data.azurerm_client_config.currently.tenant_id
  object_id = azurerm_linux_web_app.app.identity[0].principal_id
  secret_permissions = ["Get","List"]
}
*/

//newer preffered way
resource "azurerm_role_assignment" "app_keyvault" {
  scope = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User" // provides Get nad List access
  principal_id = azurerm_linux_web_app.app.identity[0].principal_id
}

resource "azurerm_role_assignment" "web_keyvault" {
  scope = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User" // provides Get and List access
  principal_id = azurerm_linux_web_app.web.identity[0].principal_id
}


//adding the  MSSQL password into key vault

/*resource "azurerm_key_vault_secret" "sql_password" {
  name = "sql-admin-password"
  key_vault_id = azurerm_key_vault.main.id
  value = var.sql_admin_password
  
  // explicitly tells Terraform "create the role assignments before this secret" — normally Terraform figures out order
  // automatically via references, but since nothing here directly references the role assignments, we state 
  // the dependency explicitly to avoid a possible permissions timing issue (though with RBAC, whoever's running 
  // terraform apply — you — already has full owner access, so this is more of a safety habit than a strict requirement 
  // here)

  #depends_on = [ 
    #azurerm_role_assignment.app_keyvault,
    #azurerm_role_assignment.web_keyvault
   #] 
    //removed the above block 
    # depends_on removed - was causing a circular dependency:
    # App Service (app_settings needs Secret) -> Secret (depends_on needed Role Assignment)
    # -> Role Assignment (needs App Service identity) -> back to App Service. No valid build order.
    # Removing this breaks the loop; Role Assignment still correctly waits on App Service via its
    # own real reference to the identity - this depends_on was redundant anyway.
}*/

//key vault needs write access for the person/identity running terraofrm apply without the block below it errors out
resource "azurerm_role_assignment" "terraform_keyvault_user" {
  scope = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  #commenting the code below to avoid terraform flip-flop when we run it manually and via github workflow
  #principal_id = data.azurerm_client_config.currently.object_id
  principal_id = "9a9deb46-694d-4827-b6b1-da34e1f14104"  # hardcoded to your personal account - avoids flip-flopping between local runs (you) and pipeline runs (Service Principal)
}

resource "azurerm_role_assignment" "terraform_keyvault_pipeline" {
   scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id          = "cdf02ff5-dc02-4fba-b71f-4928fddeb999"  # GitHub Actions Service Principal (pipeline runs)
}