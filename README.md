# Azure 3-Tier Infrastructure — Portfolio Project

A privately-networked 3-tier web application on Azure, provisioned entirely through Terraform, with zero stored credentials anywhere in the stack. Built over 7 weeks as a hands-on cloud engineering portfolio project — every resource, decision, and bug documented below.

## Architecture

```
Internet
   │
   ▼
Web App Service (public-facing)
   │
   ▼
┌─────────────────────────── VNet 10.0.0.0/16 ───────────────────────────┐
│                                                                         │
│  App subnet                    Data subnet          Key Vault subnet   │
│  App Service ─────────────────▶ SQL private ──┐     ▶ Secrets private  │
│  (VNet integrated)                endpoint     │       endpoint        │
│                                                 │                       │
│  Private DNS zones (linked to VNet) resolve SQL and Key Vault names   │
│  to their private IPs — public access is disabled on both             │
│                                                                         │
│  Managed Identity — app reads its SQL password from Key Vault live,   │
│  at runtime, using its own Azure AD identity. No stored credentials.  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────┘

App Insights + Log Analytics ── alerts on 5xx rate & SQL CPU% ── email

GitHub Actions (OIDC, no stored secrets) ── plan on PR, apply on merge
```

## Stack

- **IaC**: Terraform, remote state in Azure Storage
- **Compute**: Azure App Service (Linux, Python/Flask), split into web and app tiers on one shared Service Plan
- **Data**: Azure SQL Database (serverless, auto-pause), private endpoint only
- **Secrets**: Azure Key Vault (RBAC), accessed via System-Assigned Managed Identity
- **Networking**: VNet with 4 subnets, per-subnet NSGs, private endpoints + private DNS for SQL and Key Vault
- **CI/CD**: GitHub Actions, OIDC federation to Azure (no stored Azure credentials)
- **Monitoring**: Application Insights, Log Analytics, metric alerts, Azure Monitor Workbook dashboard

## Key architectural decisions

**Private networking everywhere.** Both SQL and Key Vault have `public_network_access_enabled = false`. Reaching them requires a private endpoint inside the VNet plus a matching private DNS zone — since applications resolve services by hostname, not raw IP, and Azure SQL's TLS certificate is issued for the hostname specifically.

**RBAC over Access Policies for Key Vault.** Access Policies are a Key-Vault-only permission model. RBAC is Azure's universal system, reused consistently across every resource in this project, and supports scoping down to an individual secret — Access Policies can't go below whole-vault granularity.

**Managed Identity, not stored passwords.** Both App Services authenticate to Key Vault using a System-Assigned Identity. The SQL password itself is fetched live at runtime via App Service's `@Microsoft.KeyVault(...)` reference syntax — the app code never touches Key Vault's API directly, and the raw secret value never sits in Terraform state.

**OIDC for CI/CD, not a service principal secret.** GitHub Actions authenticates to Azure via a federated identity credential — a short-lived, cryptographically signed token exchange, with zero long-lived credentials stored in GitHub.

**Least-privilege scoping throughout.** NSGs allow only the specific tier-to-tier traffic required (web→app on 443, app→data on 1433, app→keyvault on 443), with an explicit deny-all beneath each. The CI/CD Service Principal is scoped to only the two resource groups it needs, not the subscription.

**Dashboards built manually, not in Terraform.** Azure Monitor Workbook JSON is notoriously tedious to hand-author — even IaC-mature teams typically build these in the Portal UI. A deliberate, documented tradeoff rather than a gap.

## Cost management

Serverless SQL (auto-pauses after 60 min idle), Basic-tier App Service Plan, and destroy-between-sessions kept the full 7-week build under ~$40–50 total, versus an estimated $180–220/month if left running continuously.

## Real problems hit and solved

This project generated a substantial troubleshooting log — quota limits on a new subscription, a region-specific SQL provisioning restriction, Terraform state drift during a region migration, a genuine chicken-and-egg deadlock between Terraform and a private-only Key Vault, a circular dependency, GitHub's new (July 2026) immutable OIDC subject format, and role-assignment drift caused by a dynamic identity lookup. Full writeups live in the project's internal notes; happy to walk through any of them.

## Monitoring, proven not assumed

The 5xx alert wasn't just configured — it was tested. A real fault was injected (a temporarily broken SQL password), confirmed via repeated failing requests, watched live in the dashboard, reverted, and the resulting alert email was confirmed to arrive before recovery was verified.

## What's not here (yet)

No Application Gateway / WAF, no auto-scaling, no multi-region failover, single environment (no dev/staging/prod separation). Deliberately scoped for a focused, deep 7-week build rather than a maximally broad one.
