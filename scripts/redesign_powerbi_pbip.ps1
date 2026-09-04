param(
    [string]$ProjectRoot = "powerbi/AMN_Healthcare_Dashboard"
)

$ErrorActionPreference = "Stop"
$projectPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $ProjectRoot))
$reportRoot = Get-ChildItem -LiteralPath $projectPath -Directory -Filter "*.Report" | Select-Object -First 1 -ExpandProperty FullName
$definitionRoot = Join-Path $reportRoot "definition"
$pagesRoot = Join-Path $definitionRoot "pages"

$pageSubtitles = @{
    "Executive Overview" = "Enterprise staffing performance and demand"
    "Recruiting & Candidates" = "Candidate availability, credentials and placement"
    "Staffing Operations" = "Hospital demand, fulfillment and worked hours"
    "Payroll & Pipeline Health" = "Workforce cost and data-platform reliability"
}

function Save-JsonFile {
    param([string]$Path, $Value)
    $json = $Value | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Get-QueryRefs {
    param($Visual)
    $refs = @()
    if ($Visual.visual.query.queryState) {
        foreach ($role in $Visual.visual.query.queryState.PSObject.Properties) {
            foreach ($projection in $role.Value.projections) {
                if ($projection.queryRef) { $refs += [string]$projection.queryRef }
            }
        }
    }
    return $refs
}

function Add-TitleVisual {
    param([string]$PagePath, [string]$PageTitle, [string]$Subtitle)

    $name = "amnpageheader00000001"
    $folder = Join-Path $PagePath "visuals/$name"
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $title = [ordered]@{
        '$schema' = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.12.0/schema.json"
        name = $name
        position = [ordered]@{ x = 24; y = 14; z = 12000; height = 58; width = 680; tabOrder = 0 }
        visual = [ordered]@{
            visualType = "textbox"
            objects = [ordered]@{
                general = @([ordered]@{
                    properties = [ordered]@{
                        paragraphs = @(
                            [ordered]@{
                                textRuns = @([ordered]@{
                                    value = $PageTitle
                                    textStyle = [ordered]@{ fontFamily = "Segoe UI Semibold"; fontSize = "24px"; fontWeight = "bold"; color = "#59324F" }
                                })
                                horizontalTextAlignment = "left"
                            },
                            [ordered]@{
                                textRuns = @([ordered]@{
                                    value = $Subtitle
                                    textStyle = [ordered]@{ fontFamily = "Segoe UI"; fontSize = "10px"; color = "#6E7378" }
                                })
                                horizontalTextAlignment = "left"
                            }
                        )
                    }
                })
            }
            visualContainerObjects = [ordered]@{
                background = @([ordered]@{ properties = [ordered]@{ show = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = "false" } } } } })
                border = @([ordered]@{ properties = [ordered]@{ show = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = "false" } } } } })
                padding = @([ordered]@{ properties = [ordered]@{
                    top = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = "0D" } } }
                    bottom = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = "0D" } } }
                    left = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = "0D" } } }
                    right = [ordered]@{ expr = [ordered]@{ Literal = [ordered]@{ Value = "0D" } } }
                } })
            }
        }
    }
    Save-JsonFile (Join-Path $folder "visual.json") $title
}

foreach ($pageDirectory in Get-ChildItem -LiteralPath $pagesRoot -Directory) {
    $pagePath = $pageDirectory.FullName
    $page = Get-Content -LiteralPath (Join-Path $pagePath "page.json") -Raw | ConvertFrom-Json
    $visualFiles = @(Get-ChildItem -LiteralPath (Join-Path $pagePath "visuals") -Filter "visual.json" -Recurse)
    $cards = @()
    $charts = @()
    $slicers = @()

    foreach ($file in $visualFiles) {
        $visual = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        if ($visual.name -eq "amnpageheader00000001") { continue }
        $item = [pscustomobject]@{ File = $file.FullName; Json = $visual; Refs = @(Get-QueryRefs $visual) }
        switch ($visual.visual.visualType) {
            "cardVisual" { $cards += $item }
            "slicer" { $slicers += $item }
            default { $charts += $item }
        }
    }

    # Payroll combines business and platform KPIs. Keep the six strongest
    # executive callouts visible so the one-row strip remains readable.
    if ($page.displayName -eq "Payroll & Pipeline Health") {
        $keepRefs = @(
            "FACT_PAYROLL.Gross Payroll",
            "FACT_PAYROLL.Net Payroll",
            "FACT_PAYROLL.Overtime Pay",
            "FACT_PAYROLL.Average Hourly Pay",
            "VW_PIPELINE_RUNS.Pipeline Success Rate",
            "VW_PIPELINE_RUNS.SLA Compliance"
        )
        foreach ($card in $cards) {
            $card.Json | Add-Member -Force -NotePropertyName isHidden -NotePropertyValue (-not ($card.Refs | Where-Object { $_ -in $keepRefs }))
            Save-JsonFile $card.File $card.Json
        }
        $cards = @($cards | Where-Object { $_.Refs | Where-Object { $_ -in $keepRefs } })
    }

    $slicerCount = [math]::Min(2, $slicers.Count)
    for ($index = 0; $index -lt $slicers.Count; $index++) {
        $slicer = $slicers[$index]
        if ($index -lt $slicerCount) {
            $slicer.Json.position.x = 742 + ($index * 258)
            $slicer.Json.position.y = 18
            $slicer.Json.position.width = 242
            $slicer.Json.position.height = 58
            $slicer.Json.position.z = 11000 + $index
            $slicer.Json | Add-Member -Force -NotePropertyName isHidden -NotePropertyValue $false
        }
        else {
            $slicer.Json | Add-Member -Force -NotePropertyName isHidden -NotePropertyValue $true
        }
        Save-JsonFile $slicer.File $slicer.Json
    }

    $cardCount = $cards.Count
    if ($cardCount -gt 0) {
        $gap = 10
        $cardWidth = [math]::Floor((1232 - (($cardCount - 1) * $gap)) / $cardCount)
        for ($index = 0; $index -lt $cardCount; $index++) {
            $card = $cards[$index]
            $card.Json.position.x = 24 + ($index * ($cardWidth + $gap))
            $card.Json.position.y = 91
            $card.Json.position.width = $cardWidth
            $card.Json.position.height = 108
            $card.Json.position.z = 1000 + $index
            $card.Json | Add-Member -Force -NotePropertyName isHidden -NotePropertyValue $false
            Save-JsonFile $card.File $card.Json
        }
    }

    $chartCount = $charts.Count
    if ($chartCount -eq 1) {
        $charts[0].Json.position.x = 24; $charts[0].Json.position.y = 228
        $charts[0].Json.position.width = 1232; $charts[0].Json.position.height = 456
    }
    elseif ($chartCount -eq 2) {
        for ($index = 0; $index -lt 2; $index++) {
            $charts[$index].Json.position.x = 24 + ($index * 626)
            $charts[$index].Json.position.y = 228
            $charts[$index].Json.position.width = 606
            $charts[$index].Json.position.height = 456
        }
    }
    elseif ($chartCount -ge 3) {
        $chartWidth = [math]::Floor((1232 - (($chartCount - 1) * 14)) / $chartCount)
        for ($index = 0; $index -lt $chartCount; $index++) {
            $charts[$index].Json.position.x = 24 + ($index * ($chartWidth + 14))
            $charts[$index].Json.position.y = 228
            $charts[$index].Json.position.width = $chartWidth
            $charts[$index].Json.position.height = 456
        }
    }
    for ($index = 0; $index -lt $chartCount; $index++) {
        $charts[$index].Json.position.z = 5000 + $index
        Save-JsonFile $charts[$index].File $charts[$index].Json
    }

    Add-TitleVisual $pagePath $page.displayName $pageSubtitles[$page.displayName]
}

$themePath = Get-ChildItem -LiteralPath (Join-Path $reportRoot "StaticResources/RegisteredResources") -Filter "AMN_Healthcare*.json" | Select-Object -First 1 -ExpandProperty FullName
$theme = Get-Content -LiteralPath $themePath -Raw | ConvertFrom-Json
$theme.name = "AMN Executive Healthcare"
$theme.dataColors = @("#693552", "#C45D6D", "#E28B74", "#D4A346", "#438B87", "#7770A3", "#45708D", "#A65378")
$theme.background = "#FAF8F7"
$theme.foreground = "#28343D"
$theme.tableAccent = "#693552"
$theme.good = "#438B73"
$theme.neutral = "#D4A346"
$theme.bad = "#C45D6D"
$theme.visualStyles.'*'.'*'.title[0].fontColor.solid.color = "#3B2F38"
$theme.visualStyles.'*'.'*'.background[0].color.solid.color = "#FFFFFF"
$theme.visualStyles.'*'.'*'.border[0].color.solid.color = "#E6DDE1"
$theme.visualStyles.'*'.'*'.border[0].radius = 8
$theme.visualStyles.page.'*'.background[0].color.solid.color = "#FAF8F7"
$theme.textClasses.title.color = "#59324F"
$theme.textClasses.header.color = "#59324F"
$theme.textClasses.callout.color = "#693552"
Save-JsonFile $themePath $theme

Write-Output "Redesigned PBIP report at $projectPath"
