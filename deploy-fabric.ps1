param(
    [string]$ConfigPath = ".\fabric-config.local.json",
    [string]$TargetFolderName = "",
    [string]$NameSuffix = "",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    Split-Path -Parent $MyInvocation.ScriptName
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Encode-TextBase64 {
    param([string]$Text)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Encode-BytesBase64 {
    param([byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes)
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseResolved = (Resolve-Path -LiteralPath $BasePath).Path
    $targetResolved = (Resolve-Path -LiteralPath $TargetPath).Path

    if (-not $baseResolved.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $baseResolved = $baseResolved + [IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseResolved)
    $targetUri = New-Object System.Uri($targetResolved)
    [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace("/", "\")
}

function Get-AzAccessTokenValue {
    param([string]$Resource)

    $token = az account get-access-token --resource $Resource --query accessToken -o tsv
    if (-not $token) {
        throw "Could not obtain Azure access token for $Resource."
    }
    $token.Trim()
}

function Invoke-FabricRest {
    param(
        [ValidateSet("GET", "POST", "PATCH")]
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        [object]$Body = $null,
        [int[]]$ExpectedStatusCodes = @(200)
    )

    $jsonBody = $null
    if ($null -ne $Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 100
    }

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Accept = "application/json"
    foreach ($key in $Headers.Keys) {
        if ($key -eq "Content-Type") { continue }
        $request.Headers[$key] = [string]$Headers[$key]
    }

    if ($null -ne $jsonBody) {
        $bytes = [Text.Encoding]::UTF8.GetBytes($jsonBody)
        $request.ContentType = "application/json"
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Dispose()
    }

    try {
        $rawResponse = $request.GetResponse()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $rawResponse = $_.Exception.Response
        } else {
            throw
        }
    }

    $reader = New-Object System.IO.StreamReader($rawResponse.GetResponseStream())
    $content = $reader.ReadToEnd()
    $reader.Dispose()

    $response = [pscustomobject]@{
        StatusCode = [int]$rawResponse.StatusCode
        Headers = $rawResponse.Headers
        Content = $content
    }

    if ($ExpectedStatusCodes -notcontains [int]$response.StatusCode) {
        throw "$Method $Uri failed with $($response.StatusCode): $($response.Content)"
    }
    return $response
}

function Get-JsonResponse {
    param([object]$Response)

    if (-not $Response.Content -or $Response.Content -eq "null") {
        return $null
    }
    $Response.Content | ConvertFrom-Json
}

function Wait-FabricOperation {
    param(
        [object]$Response,
        [hashtable]$Headers
    )

    if (@(200, 201) -contains [int]$Response.StatusCode) {
        return Get-JsonResponse -Response $Response
    }

    if ([int]$Response.StatusCode -ne 202) {
        throw "Unexpected long-running operation status $($Response.StatusCode)."
    }

    $location = $Response.Headers["Location"]
    if (-not $location) {
        return $null
    }

    do {
        $retryAfter = $Response.Headers["Retry-After"]
        if (-not $retryAfter) { $retryAfter = 10 }
        Start-Sleep -Seconds ([int]$retryAfter)
        $Response = Invoke-FabricRest -Method GET -Uri $location -Headers $Headers -ExpectedStatusCodes @(200, 202)
    } while ([int]$Response.StatusCode -eq 202)

    $operation = Get-JsonResponse -Response $Response
    if ($operation -and $operation.status -in @("Failed", "Cancelled")) {
        throw "Fabric operation failed: $($Response.Content)"
    }

    $resultUri = "$location/result"
    $result = Invoke-FabricRest -Method GET -Uri $resultUri -Headers $Headers -ExpectedStatusCodes @(200, 202, 404)
    if ([int]$result.StatusCode -eq 200 -and $result.Content -and $result.Content -ne "null") {
        return $result.Content | ConvertFrom-Json
    }
    return $operation
}

function Get-WorkspaceItems {
    param([string]$WorkspaceId, [hashtable]$Headers)

    $response = Invoke-FabricRest -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items?recursive=true" -Headers $Headers
    (Get-JsonResponse -Response $response).value
}

function Get-WorkspaceFolders {
    param([string]$WorkspaceId, [hashtable]$Headers)

    $response = Invoke-FabricRest -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/folders?recursive=true" -Headers $Headers
    (Get-JsonResponse -Response $response).value
}

function Find-ItemByName {
    param(
        [object[]]$Items,
        [string]$Type,
        [string]$DisplayName,
        [string]$FolderId
    )

    $Items | Where-Object {
        $_.type -eq $Type -and $_.displayName -eq $DisplayName -and ($FolderId -eq "" -or $_.folderId -eq $FolderId)
    } | Select-Object -First 1
}

function Ensure-Folder {
    param(
        [string]$WorkspaceId,
        [string]$FolderName,
        [hashtable]$Headers
    )

    if (-not $FolderName) {
        return $null
    }

    $folders = Get-WorkspaceFolders -WorkspaceId $WorkspaceId -Headers $Headers
    $existing = $folders | Where-Object { $_.displayName -eq $FolderName } | Select-Object -First 1
    if ($existing) {
        return $existing
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would create folder '$FolderName'."
        return [pscustomobject]@{ id = "<folder-id>"; displayName = $FolderName }
    }

    $response = Invoke-FabricRest `
        -Method POST `
        -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/folders" `
        -Headers $Headers `
        -Body @{ displayName = $FolderName } `
        -ExpectedStatusCodes @(201)
    Get-JsonResponse -Response $response
}

function Ensure-Item {
    param(
        [string]$WorkspaceId,
        [string]$CollectionName,
        [string]$Type,
        [string]$DisplayName,
        [string]$FolderId,
        [hashtable]$Headers,
        [object]$Definition = $null,
        [object]$CreationPayload = $null,
        [string]$Description = ""
    )

    $items = Get-WorkspaceItems -WorkspaceId $WorkspaceId -Headers $Headers
    $existing = Find-ItemByName -Items $items -Type $Type -DisplayName $DisplayName -FolderId $FolderId

    if ($existing -and $Definition) {
        if ($WhatIf) {
            Write-Host "[WhatIf] Would update $Type '$DisplayName'."
            return $existing
        }

        $typePath = switch ($Type) {
            "Notebook" { "notebooks" }
            "SemanticModel" { "semanticModels" }
            "Report" { "reports" }
            default { throw "UpdateDefinition is not implemented for type $Type." }
        }

        $updateResponse = Invoke-FabricRest `
            -Method POST `
            -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/$typePath/$($existing.id)/updateDefinition" `
            -Headers $Headers `
            -Body @{ definition = $Definition } `
            -ExpectedStatusCodes @(200, 202)
        [void](Wait-FabricOperation -Response $updateResponse -Headers $Headers)
        return $existing
    }

    if ($existing) {
        return $existing
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would create $Type '$DisplayName'."
        return [pscustomobject]@{ id = "<item-id>"; displayName = $DisplayName; type = $Type; folderId = $FolderId }
    }

    $body = @{
        displayName = $DisplayName
        description = $Description
    }
    if ($FolderId) {
        $body.folderId = $FolderId
    }
    if ($Definition) {
        $body.definition = $Definition
    }
    if ($CreationPayload) {
        $body.creationPayload = $CreationPayload
    }

    $createResponse = Invoke-FabricRest `
        -Method POST `
        -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/$CollectionName" `
        -Headers $Headers `
        -Body $body `
        -ExpectedStatusCodes @(201, 202)

    $result = Wait-FabricOperation -Response $createResponse -Headers $Headers
    if ($result -and $result.id) {
        return $result
    }

    $items = Get-WorkspaceItems -WorkspaceId $WorkspaceId -Headers $Headers
    $created = Find-ItemByName -Items $items -Type $Type -DisplayName $DisplayName -FolderId $FolderId
    if (-not $created) {
        throw "Could not locate created $Type '$DisplayName'."
    }
    return $created
}

function Patch-NotebookObject {
    param(
        [object]$Notebook,
        [object]$Config,
        [string]$LakehouseId,
        [string]$LakehouseName,
        [string]$WorkspaceId
    )

    foreach ($cell in $Notebook.cells) {
        if ($cell.cell_type -ne "code") { continue }
        $newSource = New-Object System.Collections.Generic.List[string]
        foreach ($line in $cell.source) {
            if ($line -match '^vaulturl\s*=') {
                $newSource.Add("vaulturl = `"$($Config.identity.key_vault_url)`"`n")
            } elseif ($line -match '^TENANT_ID\s*=') {
                $newSource.Add("TENANT_ID = `"$($Config.identity.tenant_id)`"`n")
            } elseif ($line -match '^TABLE_NAME\s*= "pbi_activity_events"') {
                $newSource.Add("TABLE_NAME = `"$($Config.notebooks.activity_table_name)`"`n")
            } elseif ($line -match '^TABLE_NAME\s*= "pbi_current_reports_inventory"') {
                $newSource.Add("TABLE_NAME = `"$($Config.notebooks.reports_inventory_table_name)`"`n")
            } elseif ($line -match '^TABLE_NAME\s*= "pbi_licensed_users"') {
                $newSource.Add("TABLE_NAME = `"$($Config.notebooks.licensed_users_table_name)`"`n")
            } elseif ($line -match '^MAX_DAYS_BACKFILL\s*=') {
                $newSource.Add("MAX_DAYS_BACKFILL = $($Config.notebooks.max_days_backfill) # The max possible is 27`n")
            } elseif ($line -match '^WORKSPACE_FILTER\s*= False') {
                $flag = if ($Config.notebooks.workspace_filter_enabled) { '$True' } else { '$False' }
                $newSource.Add("WORKSPACE_FILTER = $flag`n")
            } else {
                $newSource.Add($line)
            }
        }
        $cell.source = $newSource
        if ($cell.PSObject.Properties.Name -contains "outputs") { $cell.outputs = @() }
        if ($cell.PSObject.Properties.Name -contains "execution_count") { $cell.execution_count = $null }
    }

    if (-not $Notebook.metadata) {
        $Notebook | Add-Member -MemberType NoteProperty -Name metadata -Value ([pscustomobject]@{})
    }
    if (-not $Notebook.metadata.dependencies) {
        $Notebook.metadata | Add-Member -MemberType NoteProperty -Name dependencies -Value ([pscustomobject]@{})
    }

    $lakehouseDependency = [pscustomobject]@{
        default_lakehouse = $LakehouseId
        default_lakehouse_name = $LakehouseName
        default_lakehouse_workspace_id = $WorkspaceId
        known_lakehouses = @(
            [pscustomobject]@{ id = $LakehouseId }
        )
    }

    if ($Notebook.metadata.dependencies.PSObject.Properties.Name -contains "lakehouse") {
        $Notebook.metadata.dependencies.lakehouse = $lakehouseDependency
    } else {
        $Notebook.metadata.dependencies | Add-Member -MemberType NoteProperty -Name lakehouse -Value $lakehouseDependency
    }

    return $Notebook
}

function New-NotebookDefinition {
    param(
        [string]$DisplayName,
        [string]$NotebookPath,
        [object]$Config,
        [string]$LakehouseId,
        [string]$LakehouseName,
        [string]$WorkspaceId
    )

    $notebook = Read-JsonFile -Path $NotebookPath
    $patched = Patch-NotebookObject -Notebook $notebook -Config $Config -LakehouseId $LakehouseId -LakehouseName $LakehouseName -WorkspaceId $WorkspaceId
    $notebookJson = $patched | ConvertTo-Json -Depth 100

    $platform = @{
        '$schema' = "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json"
        metadata = @{
            type = "Notebook"
            displayName = $DisplayName
        }
        config = @{
            version = "2.0"
            logicalId = [guid]::NewGuid().Guid
        }
    } | ConvertTo-Json -Depth 20

    @{
        format = "ipynb"
        parts = @(
            @{
                path = "notebook-content.ipynb"
                payload = Encode-TextBase64 -Text $notebookJson
                payloadType = "InlineBase64"
            },
            @{
                path = ".platform"
                payload = Encode-TextBase64 -Text $platform
                payloadType = "InlineBase64"
            }
        )
    }
}

function New-SemanticModelDefinition {
    param([string]$RepoRoot, [object]$Config)

    $modelRoot = Join-Path $RepoRoot "pbi\PowerBI_Usage_Model.SemanticModel"
    $parts = New-Object System.Collections.Generic.List[object]

    Get-ChildItem -LiteralPath $modelRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relativePath = (Get-RelativePathCompat -BasePath $modelRoot -TargetPath $_.FullName).Replace("\", "/")
        if ($relativePath -eq "definition/expressions.tmdl") {
            $content = Get-Content -LiteralPath $_.FullName -Raw
            $content = [regex]::Replace($content, 'expression ''WarehouseHost'' = ".*?"', "expression 'WarehouseHost' = `"$($Config.fabric.warehouse_sql_endpoint)`"")
            $content = [regex]::Replace($content, 'expression ''WarehouseDatabase'' = ".*?"', "expression 'WarehouseDatabase' = `"$($Config.fabric.warehouse_name)`"")
            $payload = Encode-TextBase64 -Text $content
        } else {
            $payload = Encode-BytesBase64 -Bytes ([IO.File]::ReadAllBytes($_.FullName))
        }
        $parts.Add(@{
            path = $relativePath
            payload = $payload
            payloadType = "InlineBase64"
        })
    }

    @{ parts = $parts }
}

function New-ReportDefinition {
    param(
        [string]$RepoRoot,
        [string]$WorkspaceName,
        [string]$SemanticModelName,
        [string]$SemanticModelId
    )

    $reportRoot = Join-Path $RepoRoot "pbi\PowerBI_Usage_Model.Report"
    $parts = New-Object System.Collections.Generic.List[object]

    Get-ChildItem -LiteralPath $reportRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relativePath = (Get-RelativePathCompat -BasePath $reportRoot -TargetPath $_.FullName).Replace("\", "/")
        if ($relativePath -eq "definition.pbir") {
            $pbir = @{
                '$schema' = "https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json"
                version = "4.0"
                datasetReference = @{
                    byConnection = @{
                        connectionString = "Data Source=`"powerbi://api.powerbi.com/v1.0/myorg/$WorkspaceName`";initial catalog=$SemanticModelName;integrated security=ClaimsToken;semanticmodelid=$SemanticModelId"
                    }
                }
            } | ConvertTo-Json -Depth 20
            $payload = Encode-TextBase64 -Text $pbir
        } else {
            $payload = Encode-BytesBase64 -Bytes ([IO.File]::ReadAllBytes($_.FullName))
        }
        $parts.Add(@{
            path = $relativePath
            payload = $payload
            payloadType = "InlineBase64"
        })
    }

    @{ parts = $parts }
}

function Write-DbtLocalConfig {
    param(
        [string]$RepoRoot,
        [object]$Config,
        [string]$LakehouseName,
        [string]$WarehouseName
    )

    $dbtLocalPath = Join-Path $RepoRoot "dbt\local.yml"
    $content = @"
profile_env:
  DBT_FABRIC_HOST: "$($Config.fabric.warehouse_sql_endpoint)"
  DBT_FABRIC_DATABASE: "$WarehouseName"
  DBT_FABRIC_SCHEMA: "$($Config.dbt.schema)"
  DBT_FABRIC_AUTHENTICATION: "$($Config.dbt.authentication)"

vars:
  lakehouse_name: "$LakehouseName"
  lakehouse_schema: "$($Config.dbt.schema)"
  activity_table_name: "$($Config.notebooks.activity_table_name)"
  reports_inventory_table_name: "$($Config.notebooks.reports_inventory_table_name)"
  licensed_users_table_name: "$($Config.notebooks.licensed_users_table_name)"
"@

    if ($WhatIf) {
        Write-Host "[WhatIf] Would write $dbtLocalPath."
        return
    }

    Set-Content -LiteralPath $dbtLocalPath -Value $content -Encoding UTF8
}

$repoRoot = Get-RepoRoot
$resolvedConfigPath = Join-Path $repoRoot $ConfigPath

if (-not (Test-Path -LiteralPath $resolvedConfigPath)) {
    throw "Config file not found: $resolvedConfigPath. Copy fabric-config.template.json to fabric-config.local.json first."
}

$config = Read-JsonFile -Path $resolvedConfigPath
$workspaceId = $config.fabric.workspace_id
$workspaceName = $config.fabric.workspace_name
$folderName = if ($TargetFolderName) { $TargetFolderName } else { "" }
$suffix = $NameSuffix

$notebookMap = @(
    @{ Path = "get_usage_data.ipynb"; Name = "get_usage_data$suffix" },
    @{ Path = "get_current_reports_inventory.ipynb"; Name = "get_current_reports_inventory$suffix" },
    @{ Path = "get_powerbi_license_data.ipynb"; Name = "get_powerbi_license_data$suffix" }
)

$lakehouseName = "$($config.fabric.lakehouse_name)$suffix"
$warehouseName = "$($config.fabric.warehouse_name)$suffix"
$semanticModelName = "PowerBI_Usage_Model$suffix"
$reportName = "PowerBI_Usage_Model$suffix"

$fabricToken = Get-AzAccessTokenValue -Resource "https://api.fabric.microsoft.com"
$headers = @{ Authorization = "Bearer $fabricToken" }

$folder = Ensure-Folder -WorkspaceId $workspaceId -FolderName $folderName -Headers $headers
$folderId = if ($folder) { $folder.id } else { "" }

$lakehouse = Ensure-Item `
    -WorkspaceId $workspaceId `
    -CollectionName "lakehouses" `
    -Type "Lakehouse" `
    -DisplayName $lakehouseName `
    -FolderId $folderId `
    -Headers $headers `
    -CreationPayload @{ enableSchemas = $true } `
    -Description "Reusable deployment lakehouse."

$warehouse = Ensure-Item `
    -WorkspaceId $workspaceId `
    -CollectionName "warehouses" `
    -Type "Warehouse" `
    -DisplayName $warehouseName `
    -FolderId $folderId `
    -Headers $headers `
    -CreationPayload @{ collationType = "Latin1_General_100_BIN2_UTF8" } `
    -Description "Reusable deployment warehouse."

if (-not $WhatIf) {
    $warehouseDetailsResponse = Invoke-FabricRest -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/warehouses/$($warehouse.id)" -Headers $headers
    $warehouseDetails = Get-JsonResponse -Response $warehouseDetailsResponse
    if ($warehouseDetails.properties.connectionString) {
        if ($config.fabric.PSObject.Properties.Name -contains "warehouse_sql_endpoint") {
            $config.fabric.warehouse_sql_endpoint = $warehouseDetails.properties.connectionString
        } else {
            $config.fabric | Add-Member -MemberType NoteProperty -Name warehouse_sql_endpoint -Value $warehouseDetails.properties.connectionString
        }
    }
}

foreach ($notebookInfo in $notebookMap) {
    $definition = New-NotebookDefinition `
        -DisplayName $notebookInfo.Name `
        -NotebookPath (Join-Path $repoRoot $notebookInfo.Path) `
        -Config $config `
        -LakehouseId $lakehouse.id `
        -LakehouseName $lakehouseName `
        -WorkspaceId $workspaceId

    [void](Ensure-Item `
        -WorkspaceId $workspaceId `
        -CollectionName "notebooks" `
        -Type "Notebook" `
        -DisplayName $notebookInfo.Name `
        -FolderId $folderId `
        -Headers $headers `
        -Definition $definition `
        -Description "Reusable deployment notebook.")
}

$semanticDefinition = New-SemanticModelDefinition -RepoRoot $repoRoot -Config $config
$semanticModel = Ensure-Item `
    -WorkspaceId $workspaceId `
    -CollectionName "semanticModels" `
    -Type "SemanticModel" `
    -DisplayName $semanticModelName `
    -FolderId $folderId `
    -Headers $headers `
    -Definition $semanticDefinition `
    -Description "Reusable deployment semantic model."

$reportDefinition = New-ReportDefinition `
    -RepoRoot $repoRoot `
    -WorkspaceName $workspaceName `
    -SemanticModelName $semanticModelName `
    -SemanticModelId $semanticModel.id

$report = Ensure-Item `
    -WorkspaceId $workspaceId `
    -CollectionName "reports" `
    -Type "Report" `
    -DisplayName $reportName `
    -FolderId $folderId `
    -Headers $headers `
    -Definition $reportDefinition `
    -Description "Reusable deployment report."

Write-DbtLocalConfig -RepoRoot $repoRoot -Config $config -LakehouseName $lakehouseName -WarehouseName $warehouseName

[pscustomobject]@{
    WorkspaceId = $workspaceId
    WorkspaceName = $workspaceName
    FolderName = $folderName
    Lakehouse = $lakehouseName
    Warehouse = $warehouseName
    SemanticModel = $semanticModelName
    Report = $reportName
    Notebooks = $notebookMap.Name
    DbtLocalConfig = "dbt/local.yml"
    WhatIf = [bool]$WhatIf
} | ConvertTo-Json -Depth 10
