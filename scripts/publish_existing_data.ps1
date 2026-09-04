[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [string]$ContainerName = "landing"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

$uploads = @(
    @{ Source = "datasets/cms/hospitals_reference.csv"; Destination = "cms/hospitals/hospitals_reference.csv" },
    @{ Source = "datasets/hr/candidates.csv"; Destination = "hr/candidates/candidates.csv" },
    @{ Source = "datasets/hr/staffing_requests.csv"; Destination = "hr/staffing_requests/staffing_requests.csv" },
    @{ Source = "datasets/hr/schedules.csv"; Destination = "hr/schedules/schedules.csv" },
    @{ Source = "datasets/hr/payroll.csv"; Destination = "hr/payroll/payroll.csv" }
)

foreach ($upload in $uploads) {
    $sourcePath = Join-Path $projectRoot $upload.Source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required existing dataset not found: $sourcePath"
    }

    Write-Host "Uploading $($upload.Source) -> $ContainerName/$($upload.Destination)"
    az storage blob upload `
        --account-name $StorageAccountName `
        --container-name $ContainerName `
        --name $upload.Destination `
        --file $sourcePath `
        --auth-mode login `
        --overwrite false `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Upload failed for $sourcePath"
    }
}

Write-Host "Existing datasets published successfully. No data was regenerated."

