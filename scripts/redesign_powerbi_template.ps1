param(
    [string]$InputFile = "powerbi/AMN_Healthcare_Dashboard_Complete.pbit",
    [string]$OutputFile = "powerbi/AMN_Healthcare_Dashboard_Executive_Experience_v2.pbit"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Set-VisualPosition {
    param($Container, [double]$X, [double]$Y, [double]$Width, [double]$Height, [int]$Z)

    $Container.x = $X
    $Container.y = $Y
    $Container.width = $Width
    $Container.height = $Height
    $Container.z = $Z

    $config = $Container.config | ConvertFrom-Json
    $position = $config.layouts[0].position
    $position.x = $X
    $position.y = $Y
    $position.width = $Width
    $position.height = $Height
    $position.z = $Z
    $Container.config = $config | ConvertTo-Json -Depth 100 -Compress
}

function Set-VisualTitle {
    param($Container, [string]$Title)

    $config = $Container.config | ConvertFrom-Json
    if ($config.singleVisual.vcObjects.title) {
        $config.singleVisual.vcObjects.title[0].properties.text.expr.Literal.Value = "'$Title'"
        if ($config.singleVisual.vcObjects.title[0].properties.show) {
            $config.singleVisual.vcObjects.title[0].properties.show.expr.Literal.Value = "true"
        }
    }
    $Container.config = $config | ConvertTo-Json -Depth 100 -Compress
}

$root = (Get-Location).Path
$inputPath = [IO.Path]::GetFullPath((Join-Path $root $InputFile))
$outputPath = [IO.Path]::GetFullPath((Join-Path $root $OutputFile))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("amn-pbi-redesign-" + [guid]::NewGuid().ToString("N"))
$tempZip = [IO.Path]::ChangeExtension($outputPath, ".zip")

try {
    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($inputPath, $tempRoot)

    $layoutPath = Join-Path $tempRoot "Report/Layout"
    $layout = [IO.File]::ReadAllText($layoutPath, [Text.Encoding]::Unicode) | ConvertFrom-Json

    foreach ($section in $layout.sections) {
        $cards = [System.Collections.Generic.List[object]]::new()
        $charts = [System.Collections.Generic.List[object]]::new()
        $slicers = [System.Collections.Generic.List[object]]::new()

        foreach ($container in $section.visualContainers) {
            $config = $container.config | ConvertFrom-Json
            switch ($config.singleVisual.visualType) {
                "cardVisual" { $cards.Add($container) }
                "slicer" { $slicers.Add($container) }
                default { $charts.Add($container) }
            }
        }

        # A clean title band is reserved at the top. Dropdown slicers provide
        # the search experience while keeping filters off the report body.
        $section.width = 1280
        $section.height = 720

        $visibleSlicers = @($slicers | Select-Object -First 2)
        $kept = [System.Collections.Generic.List[object]]::new()
        foreach ($card in $cards) { $kept.Add($card) }
        foreach ($chart in $charts) { $kept.Add($chart) }
        foreach ($slicer in $visibleSlicers) { $kept.Add($slicer) }
        $section.visualContainers = @($kept)

        $slicerWidth = 245
        for ($i = 0; $i -lt $visibleSlicers.Count; $i++) {
            $x = 740 + ($i * 260)
            Set-VisualPosition $visibleSlicers[$i] $x 18 $slicerWidth 58 (100 + $i)
            $cfg = $visibleSlicers[$i].config | ConvertFrom-Json
            if ($cfg.singleVisual.objects.general) {
                $cfg.singleVisual.objects.general[0].properties.orientation = @{ expr = @{ Literal = @{ Value = "'Dropdown'" } } }
            }
            $visibleSlicers[$i].config = $cfg | ConvertTo-Json -Depth 100 -Compress
        }

        $cardCount = $cards.Count
        if ($cardCount -gt 0) {
            $gap = 10
            $cardWidth = [math]::Floor((1240 - (($cardCount - 1) * $gap)) / $cardCount)
            for ($i = 0; $i -lt $cardCount; $i++) {
                Set-VisualPosition $cards[$i] (20 + ($i * ($cardWidth + $gap))) 95 $cardWidth 105 (10 + $i)
            }
        }

        $chartCount = $charts.Count
        if ($chartCount -eq 1) {
            Set-VisualPosition $charts[0] 20 235 1240 445 40
        }
        elseif ($chartCount -eq 2) {
            Set-VisualPosition $charts[0] 20 235 610 445 40
            Set-VisualPosition $charts[1] 650 235 610 445 41
        }
        elseif ($chartCount -ge 3) {
            $chartWidth = [math]::Floor((1240 - (($chartCount - 1) * 15)) / $chartCount)
            for ($i = 0; $i -lt $chartCount; $i++) {
                Set-VisualPosition $charts[$i] (20 + ($i * ($chartWidth + 15))) 235 $chartWidth 445 (40 + $i)
            }
        }

        foreach ($chart in $charts) {
            $cfg = $chart.config | ConvertFrom-Json
            $title = $cfg.singleVisual.vcObjects.title[0].properties.text.expr.Literal.Value
            if ($title) { Set-VisualTitle $chart $title.Trim("'") }
        }
    }

    $layoutJson = $layout | ConvertTo-Json -Depth 100 -Compress
    [IO.File]::WriteAllText($layoutPath, $layoutJson, [Text.Encoding]::Unicode)

    $themePath = Get-ChildItem -LiteralPath (Join-Path $tempRoot "Report/StaticResources/RegisteredResources") -Filter "AMN_Healthcare*.json" | Select-Object -First 1 -ExpandProperty FullName
    if ($themePath) {
        $theme = [IO.File]::ReadAllText($themePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $theme.name = "AMN Executive Healthcare"
        $theme.dataColors = @("#6A365D", "#C85A6A", "#E38B72", "#D4A64A", "#4F8F8A", "#7C75A5", "#A64D79", "#5C7896")
        $theme.background = "#FBF9F8"
        $theme.foreground = "#27313A"
        $theme.tableAccent = "#6A365D"
        $theme.good = "#3D8B73"
        $theme.neutral = "#D4A64A"
        $theme.bad = "#C85A6A"

        # Keep the original, Power BI-generated visualStyles schema intact.
        # Only top-level palette values are changed because these fields are
        # stable across Desktop versions.
        [IO.File]::WriteAllText($themePath, ($theme | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
    }

    if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force }
    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempRoot, $tempZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    Move-Item -LiteralPath $tempZip -Destination $outputPath
    Write-Output "Created $outputPath"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
