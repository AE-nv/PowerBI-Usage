# Power BI Usage Monitoring

A reusable Fabric + Power BI solution for collecting, transforming, and reporting on Power BI usage, activity events, report inventory, and license usage.

## What this repo contains

- `get_usage_data.ipynb`: incremental ingestion of Power BI Admin Activity Events into a Fabric lakehouse Delta table
- `get_current_reports_inventory.ipynb`: snapshot of currently existing Power BI reports
- `get_powerbi_license_data.ipynb`: snapshot of Power BI licensed users
- `dbt/`: transformations from lakehouse tables into warehouse dimensions and facts
- `pbi/`: PBIP project for the semantic model and report

## Intended data flow

```text
Power BI Admin Activity Events API + Power BI REST API + Microsoft Graph API
        ->
Fabric notebooks
        ->
Lakehouse Delta tables
        ->
dbt models in Fabric warehouse
        ->
Semantic model
        ->
Power BI report
```

## Reusability status

This repo is meant to be reusable across customers or internal workspaces, but it is not infrastructure-as-code by itself.

What is reusable:

- notebook logic
- dbt model logic
- semantic model structure
- report layout

What still needs setup per environment:

- Fabric workspace, lakehouse, and warehouse
- Entra app registration and permissions
- Azure Key Vault and secret names

Use [fabric-config.template.json](C:\Users\DriesCornelissen\projects\bench\pbi usage dashboard\data_ai_repo_DPA\Power%20BI%20Usage%20report\fabric-config.template.json) as the single handover checklist for those values.

## Prerequisites

### 1. Service principal

Create an Entra ID app registration and collect:

- tenant ID
- client ID
- client secret

The service principal is used for:

- Power BI Admin Activity Events API
- Power BI REST API
- Microsoft Graph API

### 2. Security group

Create a security group and add the service principal to it.

### 3. Tenant settings

A Fabric or Power BI admin must enable:

```text
Fabric Admin Portal
-> Tenant settings
-> Service principals can access read-only admin APIs
```

Add the security group to that setting.

### 4. API permissions

Grant the required Power BI and Microsoft Graph permissions and admin consent.

At minimum, verify that the app can read:

- Power BI admin activity
- Power BI workspace/report inventory
- Microsoft Graph license assignment data

### 5. Key Vault

Store the service principal values in Azure Key Vault.

Default secret names expected by the notebooks:

- `usageclient`
- `usagesecret`

If you use different names, update the notebook code accordingly.

## Setup checklist

Fill in these values for the target environment:

1. Copy `fabric-config.template.json` to `fabric-config.local.json`.
2. Fill in the workspace, lakehouse, warehouse, Key Vault, and tenant values.
3. Choose one deployment path:
   manual deployment or `deploy-fabric.ps1`.
4. Run the notebooks, dbt, and semantic model refresh in the right order.

## Deployment paths

There are two supported ways to deploy this repo.

### Option 1. Deploy with the PowerShell script

Use this when you want the repo to create or reuse the Fabric items and patch the assets for you.

Steps:

1. Copy `fabric-config.template.json` to `fabric-config.local.json`.
2. Fill in the required values in `fabric-config.local.json`.
3. Sign in with Azure CLI:

```powershell
az login
```

4. Run the deployment script:

```powershell
.\deploy-fabric.ps1
```

Optional examples:

```powershell
.\deploy-fabric.ps1 -TargetFolderName test
.\deploy-fabric.ps1 -TargetFolderName test -NameSuffix _test
.\deploy-fabric.ps1 -WhatIf
```

What the script does:

- creates or reuses the target Fabric folder
- creates or reuses the lakehouse and warehouse
- discovers the lakehouse attachment values and warehouse SQL endpoint
- patches and publishes the notebooks
- patches and publishes the semantic model
- patches and publishes the report
- generates `dbt/local.yml`

What still remains after the script:

- run the notebooks
- run dbt
- refresh the semantic model

The script:

- reads `fabric-config.local.json`
- writes `dbt/local.yml`
- supports `-TargetFolderName`, `-NameSuffix`, and `-WhatIf`
- assumes Azure CLI is installed and you are signed in with `az login`
- assumes the signed-in identity can create and update Fabric items in the target workspace
- does not require you to provide the lakehouse item ID or warehouse SQL endpoint, because those are discovered automatically

### Option 2. Deploy manually

Use this when you do not want to rely on the deployment script.

Steps:

1. Create or choose the target Fabric workspace.
2. Create or choose the target lakehouse and warehouse.
3. Import the three notebooks into Fabric.
4. Update notebook parameter values and attach the correct lakehouse.
5. Set up dbt local config and run dbt.
6. Update the semantic model connection values.
7. Publish the semantic model and report.
8. Set schedules and refresh order.

## Notebook setup

If you use `deploy-fabric.ps1`, the notebooks are published with the correct lakehouse attachment automatically.

If you set things up manually, import the three notebooks into the target Fabric workspace and attach the target lakehouse yourself.

The notebooks intentionally ship with placeholders, not real tenant values.

Update:

- `vaulturl`
- `TENANT_ID`
- attached lakehouse metadata
- any optional workspace filter values

Manual deployment note:

- the notebooks contain placeholder values on purpose
- they will not run correctly until those values are updated for the target environment

Notebook defaults:

- activity table: `pbi_activity_events`
- reports inventory table: `pbi_current_reports_inventory`
- licensed users table: `pbi_licensed_users`
- max backfill days: `27`

Recommended schedule:

- run daily
- run early morning UTC

## dbt setup

You do not need to edit those tracked files for each environment anymore. Instead:

1. Generate or fill in `dbt/local.yml`
2. Run dbt through [dbt/run-local.ps1](C:\Users\DriesCornelissen\projects\bench\pbi usage dashboard\data_ai_repo_DPA\Power%20BI%20Usage%20report\dbt\run-local.ps1)

Template:

```text
dbt/local.template.yml
```

Run:

```powershell
.\dbt\run-local.ps1 deps
.\dbt\run-local.ps1 run
```

If you used `deploy-fabric.ps1`, `dbt/local.yml` is generated automatically.

If you are deploying manually:

1. Copy `dbt/local.template.yml` to `dbt/local.yml`
2. Fill in:
   - warehouse SQL endpoint
   - warehouse name
   - schema
   - lakehouse name
   - source table names if you changed notebook outputs

Manual direct dbt run note:

- `profiles.yml` stays generic and reads connection settings from environment variables
- `sources.yml` reads project-specific source names from dbt vars
- that is why both environment variables and `--vars` are used

If you want to run dbt directly without `run-local.ps1`, set the environment variables yourself and pass the vars explicitly:

```powershell
$env:DBT_FABRIC_HOST = "<warehouse-sql-endpoint>"
$env:DBT_FABRIC_DATABASE = "gold"
$env:DBT_FABRIC_SCHEMA = "dbo"
$env:DBT_FABRIC_AUTHENTICATION = "CLI"

dbt run --profiles-dir .\dbt --vars "{lakehouse_name: bronze, lakehouse_schema: dbo, activity_table_name: pbi_activity_events, reports_inventory_table_name: pbi_current_reports_inventory, licensed_users_table_name: pbi_licensed_users}"
```

Schedule dbt after the notebooks complete.

## Semantic model and report setup

Open [pbi/PowerBI_Usage_Model.pbip](C:\Users\DriesCornelissen\projects\bench\pbi usage dashboard\data_ai_repo_DPA\Power%20BI%20Usage%20report\pbi\PowerBI_Usage_Model.pbip) in Power BI Desktop.

Update [pbi/PowerBI_Usage_Model.SemanticModel/definition/expressions.tmdl](C:\Users\DriesCornelissen\projects\bench\pbi usage dashboard\data_ai_repo_DPA\Power%20BI%20Usage%20report\pbi\PowerBI_Usage_Model.SemanticModel\definition\expressions.tmdl):

- `WarehouseHost`
- `WarehouseDatabase`

If you use `deploy-fabric.ps1`, the semantic model and report are patched and published automatically.

If you set things up manually, update those parameters and then publish to the target workspace.

Manual deployment note:

- the semantic model ships with placeholder connection values
- manual publish requires updating `WarehouseHost` and `WarehouseDatabase` first

## Refresh order

1. notebooks
2. dbt transformations
3. semantic model refresh

## After deployment

Whether you deploy manually or with the script, the operational order is the same:

1. run the notebooks so the lakehouse tables exist and are populated
2. run dbt so the warehouse tables are created
3. refresh the semantic model
4. configure schedules in that same order

## Guidance for teammates

This repo is safe to reuse when the teammate does these things explicitly:

- creates or chooses the target Fabric workspace
- attaches the correct lakehouse to the notebooks
- updates the warehouse endpoint in dbt and the semantic model
- validates service principal permissions before first run

This repo is not yet a one-click deployment accelerator. It is a reusable solution template with a manual setup path.

## Common issues

`Empty API results`

- verify tenant settings
- verify the service principal is in the allowed security group
- verify credentials and admin consent

`Authentication errors`

- verify Key Vault URL
- verify secret names
- verify tenant ID
- verify client secret validity

`Missing historical data`

- the Activity Events API only retains 27 days

`Duplicate data`

- the activity ingestion notebook deduplicates on activity event `Id`

## References

- [Power BI Activity Events API](https://learn.microsoft.com/en-us/rest/api/power-bi/admin/get-activity-events)
- [Power BI REST API](https://learn.microsoft.com/en-us/rest/api/power-bi/)
- [Microsoft Graph overview](https://learn.microsoft.com/en-us/graph/overview)
