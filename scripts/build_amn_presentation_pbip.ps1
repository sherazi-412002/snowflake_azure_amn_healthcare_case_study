param(
    [string]$ProjectRoot = "powerbi/AMN_Healthcare_Dashboard_Presentation"
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path (Get-Location) $ProjectRoot))
$reportRoot = Get-ChildItem -LiteralPath $root -Directory -Filter "*.Report" | Select-Object -First 1 -ExpandProperty FullName
$pagesRoot = Join-Path $reportRoot "definition/pages"
$schema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.12.0/schema.json"
$script:visualIndex = 0

function Save-Json([string]$Path, $Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}

function Position([double]$X,[double]$Y,[double]$W,[double]$H) {
    $script:visualIndex++
    return [ordered]@{x=$X;y=$Y;z=($script:visualIndex*1000);height=$H;width=$W;tabOrder=($script:visualIndex*1000)}
}

function ColumnField([string]$Table,[string]$Column) {
    return [ordered]@{Column=[ordered]@{Expression=[ordered]@{SourceRef=[ordered]@{Entity=$Table}};Property=$Column}}
}

function MeasureField([string]$Table,[string]$Measure) {
    return [ordered]@{Measure=[ordered]@{Expression=[ordered]@{SourceRef=[ordered]@{Entity=$Table}};Property=$Measure}}
}

function Projection($Field,[string]$Table,[string]$Name,[bool]$Active=$false) {
    $p=[ordered]@{field=$Field;queryRef="$Table.$Name";nativeQueryRef=$Name}
    if($Active){$p.active=$true}
    return $p
}

function TitleObject([string]$Text) {
    return [ordered]@{title=@([ordered]@{properties=[ordered]@{
        text=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="'$Text'"}}}
        show=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="true"}}}
    }})}
}

function Write-Visual([string]$VisualsPath,[string]$Name,$Value) {
    Save-Json (Join-Path $VisualsPath "$Name/visual.json") $Value
}

function Add-Textbox([string]$VisualsPath,[string]$Name,[string[]]$Lines,[string[]]$Sizes,[string[]]$Colors,[double]$X,[double]$Y,[double]$W,[double]$H,[string]$Background="#FFFFFF",[bool]$ShowBackground=$false) {
    $paragraphs=@()
    $showValue=if($ShowBackground){"true"}else{"false"}
    for($i=0;$i -lt $Lines.Count;$i++) {
        $paragraphs += [ordered]@{textRuns=@([ordered]@{value=$Lines[$i];textStyle=[ordered]@{fontFamily="Segoe UI Semibold";fontSize=$Sizes[$i];color=$Colors[$i]}});horizontalTextAlignment="left"}
    }
    $v=[ordered]@{'$schema'=$schema;name=$Name;position=(Position $X $Y $W $H);visual=[ordered]@{
        visualType="textbox";objects=[ordered]@{general=@([ordered]@{properties=[ordered]@{paragraphs=$paragraphs}})}
        visualContainerObjects=[ordered]@{
            background=@(
                [ordered]@{
                    properties=[ordered]@{
                        show=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value=$showValue}}}
                        color=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="'$Background'"}}}
                    }
                }
            )
            border=@(
                [ordered]@{
                    properties=[ordered]@{
                        show=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="false"}}}
                    }
                }
            )
        }
    }}
    Write-Visual $VisualsPath $Name $v
}

function Add-Card([string]$VisualsPath,[string]$Name,[string]$Table,[string]$Measure,[double]$X,[double]$Y,[double]$W,[double]$H) {
    $v=[ordered]@{'$schema'=$schema;name=$Name;position=(Position $X $Y $W $H);visual=[ordered]@{
        visualType="cardVisual";query=[ordered]@{queryState=[ordered]@{Data=[ordered]@{projections=@(Projection (MeasureField $Table $Measure) $Table $Measure)}}};drillFilterOtherVisuals=$true
        objects=[ordered]@{
            value=@([ordered]@{properties=[ordered]@{
                fontSize=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="24D"}}}
                fontColor=[ordered]@{solid=[ordered]@{color=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="'#173B57'"}}}}}
                bold=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="true"}}}
            };selector=[ordered]@{id="default"}})
            label=@([ordered]@{properties=[ordered]@{
                show=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="true"}}}
                fontSize=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="10D"}}}
                fontColor=[ordered]@{solid=[ordered]@{color=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="'#526574'"}}}}}
            };selector=[ordered]@{id="default"}})
            outline=@([ordered]@{properties=[ordered]@{show=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="false"}}}};selector=[ordered]@{id="default"}})
            accentBar=@([ordered]@{properties=[ordered]@{
                show=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="true"}}}
                color=[ordered]@{solid=[ordered]@{color=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="'#138A86'"}}}}}
                transparency=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="0L"}}}
            };selector=[ordered]@{id="default"}})
        }
    }}
    Write-Visual $VisualsPath $Name $v
}

function Add-Slicer([string]$VisualsPath,[string]$Name,[string]$Title,[string]$Table,[string]$Column,[double]$X,[double]$Y,[double]$W,[double]$H) {
    $v=[ordered]@{'$schema'=$schema;name=$Name;position=(Position $X $Y $W $H);visual=[ordered]@{
        visualType="slicer";query=[ordered]@{queryState=[ordered]@{Values=[ordered]@{projections=@(Projection (ColumnField $Table $Column) $Table $Column $true)}}}
        objects=[ordered]@{
            data=@([ordered]@{properties=[ordered]@{mode=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="'Dropdown'"}}}}})
            header=@([ordered]@{properties=[ordered]@{
                show=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="true"}}}
                text=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="'$Title'"}}}
            }})
            selection=@([ordered]@{properties=[ordered]@{
                singleSelect=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="true"}}}
                selectAllCheckboxEnabled=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="false"}}}
            }})
        }
        visualContainerObjects=[ordered]@{padding=@([ordered]@{properties=[ordered]@{
            top=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="8D"}}};bottom=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="8D"}}}
            left=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="8D"}}};right=[ordered]@{expr=[ordered]@{Literal=[ordered]@{Value="8D"}}}
        }})};drillFilterOtherVisuals=$true
    }}
    Write-Visual $VisualsPath $Name $v
}

function Add-Bar([string]$VisualsPath,[string]$Name,[string]$Title,[string]$CategoryTable,[string]$Category,[array]$Measures,[double]$X,[double]$Y,[double]$W,[double]$H) {
    # PowerShell flattens a single nested two-item array passed to an [array]
    # parameter. Re-wrap that case so table/measure names are not treated as
    # character arrays (for example, FACT... becoming the invalid ref F.A).
    $ys=@()
    if($Measures.Count -eq 2 -and $Measures[0] -is [string]) {
        $ys += Projection (MeasureField $Measures[0] $Measures[1]) $Measures[0] $Measures[1]
    } else {
        foreach($m in $Measures){$ys += Projection (MeasureField $m[0] $m[1]) $m[0] $m[1]}
    }
    $v=[ordered]@{'$schema'=$schema;name=$Name;position=(Position $X $Y $W $H);visual=[ordered]@{
        visualType="clusteredBarChart";query=[ordered]@{queryState=[ordered]@{
            Category=[ordered]@{projections=@(Projection (ColumnField $CategoryTable $Category) $CategoryTable $Category $true)}
            Y=[ordered]@{projections=$ys}
        }}
        visualContainerObjects=(TitleObject $Title);drillFilterOtherVisuals=$true
    }}
    Write-Visual $VisualsPath $Name $v
}

function Add-Line([string]$VisualsPath,[string]$Name,[string]$Title,[string]$DateTable,[string]$DateColumn,[array]$Measures,[double]$X,[double]$Y,[double]$W,[double]$H) {
    $ys=@(); foreach($m in $Measures){$ys += Projection (MeasureField $m[0] $m[1]) $m[0] $m[1]}
    $v=[ordered]@{'$schema'=$schema;name=$Name;position=(Position $X $Y $W $H);visual=[ordered]@{
        visualType="lineChart";query=[ordered]@{queryState=[ordered]@{
            Category=[ordered]@{projections=@(Projection (ColumnField $DateTable $DateColumn) $DateTable $DateColumn $true)}
            Y=[ordered]@{projections=$ys}
        }};visualContainerObjects=(TitleObject $Title);drillFilterOtherVisuals=$true
    }}
    Write-Visual $VisualsPath $Name $v
}

function Initialize-Page([string]$PageId,[string]$PageName,[string]$PageSubtitle) {
    $script:visualIndex=0
    $pagePath=Join-Path $pagesRoot $PageId
    $visualsPath=Join-Path $pagePath "visuals"
    if(Test-Path -LiteralPath $visualsPath){Remove-Item -LiteralPath $visualsPath -Recurse -Force}
    [IO.Directory]::CreateDirectory($visualsPath)|Out-Null
    Add-Textbox $visualsPath "header000000000000001" @("AMN Healthcare Workforce Analytics","$PageName  |  $PageSubtitle") @("25px","10px") @("#173B57","#607786") 24 10 720 54 "#FFFFFF" $false
    Add-Textbox $visualsPath "nav00000000000000001" @("Executive Overview     Recruiting & Candidates     Staffing Operations     Payroll & Pipeline Health") @("10px") @("#138A86") 24 64 690 28 "#FFFFFF" $false
    Add-Slicer $visualsPath "filteryear00000000001" "Select Year" "DIM_DATE" "YEAR_NUMBER" 758 12 150 80
    Add-Slicer $visualsPath "filterhospital0000001" "Select Hospital" "DIM_HOSPITAL" "HOSPITAL_NAME" 916 12 180 80
    Add-Slicer $visualsPath "filterstate0000000001" "Select State" "DIM_HOSPITAL" "STATE" 1104 12 152 80
    return $visualsPath
}

function Add-KpiRow([string]$VisualsPath,[array]$Cards,[string]$SectionTitle="Key Performance Indicators") {
    Add-Textbox $VisualsPath "sectionkpi00000000001" @($SectionTitle) @("13px") @("#173B57") 24 100 600 24 "#FFFFFF" $false
    $gap=12; $w=[math]::Floor((1232-(($Cards.Count-1)*$gap))/$Cards.Count)
    for($i=0;$i -lt $Cards.Count;$i++){Add-Card $VisualsPath ("kpicard{0:D14}" -f $i) $Cards[$i][0] $Cards[$i][1] (24+$i*($w+$gap)) 128 $w 116}
}

# Executive Overview
$v=Initialize-Page "a301ba78bf59ff2a36bc" "Executive Overview" "Enterprise workforce demand, staffing performance, and placement coverage"
Add-KpiRow $v @(
    @("FACT_STAFFING_REQUEST","Open Requests"),@("FACT_STAFFING_REQUEST","Open Positions"),@("DIM_CANDIDATE","Active Placements"),
    @("FACT_STAFFING_REQUEST","Fill Rate"),@("FACT_STAFFING_REQUEST","Average Time to Fill"),@("FACT_PLACEMENT_SCHEDULE","Worked Hours")
) "Workforce Demand Snapshot"
Add-Textbox $v "sectioncharts000000001" @("Demand and Placement Trends") @("13px") @("#173B57") 24 254 500 24 "#FFFFFF" $false
Add-Line $v "executivetrend0000001" "Workforce Demand and Placements Over Time" "DIM_DATE" "FULL_DATE" @(@("FACT_STAFFING_REQUEST","Open Positions"),@("DIM_CANDIDATE","Active Placements")) 24 284 492 404
Add-Bar $v "executivepriority00001" "Staffing Requests by Priority" "FACT_STAFFING_REQUEST" "PRIORITY" @(@("FACT_STAFFING_REQUEST","Total Requests")) 528 284 352 404
Add-Bar $v "executivehospital00001" "Top Hospitals by Open Positions" "DIM_HOSPITAL" "HOSPITAL_NAME" @(@("FACT_STAFFING_REQUEST","Open Positions")) 892 284 364 404

# Recruiting & Candidates
$v=Initialize-Page "b47f9065df314671a201" "Recruiting & Candidate Pipeline" "Candidate availability, compliance readiness, and placement conversion"
Add-KpiRow $v @(
    @("DIM_CANDIDATE","Total Candidates"),@("DIM_CANDIDATE","Active Candidates"),@("DIM_CANDIDATE","Applications"),
    @("DIM_CANDIDATE","Credential-Ready Candidates"),@("DIM_CANDIDATE","Background-Cleared Candidates"),@("DIM_CANDIDATE","Placement Rate")
) "Recruiting Performance"
Add-Textbox $v "sectioncharts000000001" @("Candidate Journey and Supply") @("14px") @("#263238") 24 248 500 24 "#FFFFFF" $false
Add-Bar $v "recruitstatus00000001" "Candidates by Pipeline Status" "DIM_CANDIDATE" "CANDIDATE_STATUS" @(@("DIM_CANDIDATE","Total Candidates")) 24 278 390 410
Add-Bar $v "recruitreadiness000001" "Candidates by Department and Readiness" "DIM_CANDIDATE" "DEPARTMENT" @(@("DIM_CANDIDATE","Credential-Ready Candidates"),@("DIM_CANDIDATE","Background-Cleared Candidates")) 428 278 414 410
Add-Line $v "recruittrend000000001" "Applications and Placements Over Time" "DIM_DATE" "FULL_DATE" @(@("DIM_CANDIDATE","Applications"),@("DIM_CANDIDATE","Active Placements")) 856 278 400 410

# Staffing Operations
$v=Initialize-Page "c58a1076ef425782b302" "Staffing Operations" "Hospital demand coverage, scheduling capacity, and workforce utilisation"
Add-KpiRow $v @(
    @("FACT_STAFFING_REQUEST","Required Staff"),@("FACT_STAFFING_REQUEST","Available Candidate Count"),@("FACT_STAFFING_REQUEST","Open Positions"),
    @("FACT_STAFFING_REQUEST","Active Placement Count"),@("FACT_PLACEMENT_SCHEDULE","Overtime Hours"),@("FACT_STAFFING_REQUEST","Fill Rate")
) "Operational Staffing KPIs"
Add-Textbox $v "sectioncharts000000001" @("Demand Coverage and Workforce Utilisation") @("14px") @("#263238") 24 248 600 24 "#FFFFFF" $false
Add-Bar $v "staffcoverage00000001" "Required Staff versus Active Placements by Hospital" "DIM_HOSPITAL" "HOSPITAL_NAME" @(@("FACT_STAFFING_REQUEST","Required Staff"),@("FACT_STAFFING_REQUEST","Active Placement Count")) 24 278 410 410
Add-Line $v "staffhourstrend0000001" "Planned, Worked, and Overtime Hours Over Time" "DIM_DATE" "FULL_DATE" @(@("FACT_PLACEMENT_SCHEDULE","Planned Hours"),@("FACT_PLACEMENT_SCHEDULE","Worked Hours"),@("FACT_PLACEMENT_SCHEDULE","Overtime Hours")) 448 278 430 410
Add-Bar $v "staffgap000000000001" "Staffing Gap by Hospital" "DIM_HOSPITAL" "HOSPITAL_NAME" @(@("FACT_STAFFING_REQUEST","Staffing Gap")) 892 278 364 410

# Payroll & Pipeline Health
$v=Initialize-Page "d69b2187fa536893c403" "Payroll & Data Pipeline Health" "Labour-cost performance and reliability of the Snowflake data platform"
Add-KpiRow $v @(
    @("FACT_PAYROLL","Gross Payroll"),@("FACT_PAYROLL","Net Payroll"),@("FACT_PAYROLL","Benefits Deductions"),
    @("VW_PIPELINE_RUNS","Pipeline Runs"),@("VW_PIPELINE_RUNS","Pipeline Success Rate"),@("VW_PIPELINE_RUNS","Average Runtime Seconds")
) "Payroll Performance and Snowflake Reliability"
Add-Textbox $v "sectioncharts000000001" @("Payroll and Pipeline Trends") @("14px") @("#263238") 24 248 500 24 "#FFFFFF" $false
Add-Line $v "payrolltrend000000001" "Gross and Net Pay Over Time" "DIM_DATE" "FULL_DATE" @(@("FACT_PAYROLL","Gross Payroll"),@("FACT_PAYROLL","Net Payroll")) 24 278 410 410
Add-Bar $v "payrollhospital000001" "Gross Payroll by Hospital" "DIM_HOSPITAL" "HOSPITAL_NAME" @(@("FACT_PAYROLL","Gross Payroll")) 448 278 390 410
Add-Bar $v "pipelineerrors0000001" "Pipeline Runs by Status" "VW_PIPELINE_RUNS" "STATUS" @(@("VW_PIPELINE_RUNS","Pipeline Runs")) 852 278 404 410

$themePath=Get-ChildItem -LiteralPath (Join-Path $reportRoot "StaticResources/RegisteredResources") -Filter "AMN_Healthcare*.json" | Select-Object -First 1 -ExpandProperty FullName
$theme=Get-Content -LiteralPath $themePath -Raw | ConvertFrom-Json
$theme.name="AMN Healthcare Enterprise"
$theme.dataColors=@("#007F7B","#3D78A3","#8FD3CF","#5D91B5","#74AAA6","#65727C")
$theme.background="#F7FAFC";$theme.foreground="#263238";$theme.tableAccent="#138A86"
$theme.good="#2E8B57";$theme.neutral="#E0A12B";$theme.bad="#C94C4C"
$theme.visualStyles.'*'.'*'.title[0].fontColor.solid.color="#263238"
$theme.visualStyles.'*'.'*'.background[0].color.solid.color="#FFFFFF"
$theme.visualStyles.'*'.'*'.border[0].color.solid.color="#DDE4E8"
$theme.visualStyles.'*'.'*'.border[0].radius=6
$theme.visualStyles.page.'*'.background[0].color.solid.color="#F7FAFC"
$theme.textClasses.title.color="#173B57";$theme.textClasses.header.color="#263238";$theme.textClasses.label.color="#65727C";$theme.textClasses.callout.color="#173B57"
$theme.textClasses.callout.fontSize=24
$theme.visualStyles | Add-Member -NotePropertyName cardVisual -NotePropertyValue ([ordered]@{"*"=[ordered]@{
    value=@([ordered]@{bold=$true;fontSize=24;fontColor=[ordered]@{solid=[ordered]@{color="#173B57"}};'$id'="default"})
    label=@([ordered]@{show=$true;fontSize=10;fontColor=[ordered]@{solid=[ordered]@{color="#526574"}};'$id'="default"})
    cardCalloutArea=@([ordered]@{show=$true;paddingUniform=8;rectangleRoundedCurve=8;backgroundFillColor=[ordered]@{solid=[ordered]@{color="#FFFFFF"}};backgroundTransparency=0})
}}) -Force
$theme.visualStyles | Add-Member -NotePropertyName slicer -NotePropertyValue ([ordered]@{"*"=[ordered]@{
    header=@([ordered]@{fontFamily="Segoe UI Semibold";textSize=10;fontColor=[ordered]@{solid=[ordered]@{color="#173B57"}};outlineStyle=0})
    items=@([ordered]@{fontFamily="Segoe UI";textSize=9;fontColor=[ordered]@{solid=[ordered]@{color="#526574"}};outlineStyle=0;padding=2})
}}) -Force
Save-Json $themePath $theme

Write-Output "Built presentation dashboard at $root"
