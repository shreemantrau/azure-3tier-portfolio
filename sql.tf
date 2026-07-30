resource "azurerm_mssql_server" "main" {
  name = "sql-3tier-shreyas"
  resource_group_name = azurerm_resource_group.main.name
  location = azurerm_resource_group.main.location
  version = "12.0"
  administrator_login = "sqladmin"
  administrator_login_password = var.sql_admin_password

  public_network_access_enabled = false //no public ip ... we have set a private ip in data subnet just for this
}

resource "azurerm_mssql_database" "main" {
  name = "db-3tier"
  server_id = azurerm_mssql_server.main.id
  sku_name = "GP_S_GEN5_1"
  auto_pause_delay_in_minutes = 60
  min_capacity = 0.5
}

// private endpoint is a separate resource which is attached to PaaS so we need a separate block


resource "azurerm_private_endpoint" "sql" {
  name = "pe_sql"
  location = azurerm_resource_group.main.location
  subnet_id = azurerm_subnet.data.id
  resource_group_name =  azurerm_resource_group.main.name

  private_service_connection {
    name = "psc_sql"
    
    //below is not mandatory field ... but is the actual wire conencting to SQL Server
    private_connection_resource_id = azurerm_mssql_server.main.id

    //Tells which part of SQLServer to conenct to ... if it was a torage account we may have blob, file , queue, and table. 
    //Good practice to mention it everytime
    subresource_names = ["sqlServer"] // case sensitive!
    is_manual_connection = false //auto approves conenction no validaiton required. If True the SQL SErver owner need to approve conenction via Portal. Its a onetime handshake.
  }
}

resource "azurerm_private_dns_zone" "sql" {
  name = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.main.name
}

//Prvate DNS Zone is standalone ... we let VNET know that it needs to communicate with PDNSZ and Virtual Link is the way to do so.
resource "azurerm_private_dns_zone_virtual_network_link" "sql" {
  name = "sql-dns-link"
  virtual_network_id = azurerm_virtual_network.main.id
  private_dns_zone_name = azurerm_private_dns_zone.sql.name
  resource_group_name = azurerm_resource_group.main.name
}

// A RECORD maps name to IP. Use AAAA to map IPV6 and name. CNMAE for alias (redirecting). 
//MX, TXT, SRV, etc. — totally different purposes (mail routing, verification txt records, service discovery) 
// we only need A Record for now
resource "azurerm_private_dns_a_record" "sql" {
  name = azurerm_mssql_server.main.name
  zone_name = azurerm_private_dns_zone.sql.name
  resource_group_name = azurerm_resource_group.main.name
  ttl = 300
  records = [azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address]
}