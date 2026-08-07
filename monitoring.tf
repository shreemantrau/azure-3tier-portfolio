resource "azurerm_log_analytics_workspace" "name" {
  name = "law-3tier-shreyas"
  location = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku = "PerGB2018"
  retention_in_days = 30
}

//application_insight sends all the telemetry data into Log Analytics Workspace ... so it needs log_analytics_workspace.id
resource "azurerm_application_insights" "main" {
  name = "appi-3tier-shreyas"
  location = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id = azurerm_log_analytics_workspace.name.id
  application_type = "web"
}

resource "azurerm_monitor_metric_alert" "app_5xx" {
  name = "alert-app-5xx-errors"
  resource_group_name = azurerm_resource_group.main.name
  scopes = [azurerm_linux_web_app.app.id]  # which resource this alert watches
  description = "Alert when app tier returns 5xx errors"

  criteria {
    metric_namespace = "Microsoft.Web/sites"   # App Service's metric catalog
    metric_name = "Http5xx"               # server-error count (500, 502, 503, etc.)
    aggregation = "Total"                  # sum up all 5xx errors within the window
    operator = "GreaterThan"
    threshold = 5                        # alert if more than 5 occur
  }

  window_size = "PT5M"   # HOW FAR BACK to look each time - a rolling 5-minute lookback
  frequency = "PT1M"   # HOW OFTEN to re-check that rolling window - every 1 minute
  # together: every 1 minute, re-examine "how many 5xx errors happened in the trailing 5 minutes?"
  # catches sustained problems, avoids alerting on one random blip

  severity = 2   # 0 = critical, 4 = verbose. 2 = "Warning" - serious but not "system down"

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}

resource "azurerm_monitor_action_group" "main" {
  name = "ag-3tier-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name = "3tieralert"

  email_receiver {
    name = "primary-email"
    email_address = "shreyas.karandikar@gmail.com"
  }
}

resource "azurerm_monitor_metric_alert" "sql_dtu" {
  name = "alert-sql-dtu-high"
  resource_group_name = azurerm_resource_group.main.name
  scopes = [azurerm_mssql_database.main.id]   # watches the DATABASE, not the server -
                                              # compute/performance metrics (CPU, DTU) belong
                                              # to the database, not the server (which just
                                              # holds auth/firewall/management settings)
  description = "Alert when SQL database DTU/CPU usage is high"

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"   # SQL Database's metric catalog
    metric_name = "cpu_percent"    # using cpu_percent instead of raw DTU since this DB is
                                   # serverless (not fixed-DTU tier) - CPU% is the more
                                   # relevant utilization metric here
    aggregation = "Average"
    operator = "GreaterThan"
    threshold = 80               # alert if avg CPU usage exceeds 80% over the window
  }

  window_size = "PT5M"   # rolling 5-minute lookback (ISO 8601: P=Period, T=Time, 5M=5 Minutes)
  frequency = "PT1M"   # re-checked every 1 minute
  severity = 2        # 0=critical ... 4=verbose - 2 = "Warning" level

  action {
    action_group_id = azurerm_monitor_action_group.main.id   # reuses the same email notification
                                                             # group as the 5xx alert - no need to
                                                             # duplicate notification setup
  }
}