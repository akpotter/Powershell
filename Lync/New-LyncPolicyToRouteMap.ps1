﻿#Note: This version of the script is only partially complete. Throwing it out there 
#      for anyone else who wants to complete it
[CmdLetBinding()]
param(
    [Parameter(Position=0, HelpMessage="Enter a policy filter")]
    [string]$PolicyFilter = '*',
    [Parameter(Position=1, HelpMessage="File to export Graphviz definition file to.")]
    [string]$OutputFile = 'Lync-Diagram.txt'
)

$GraphVisTemplate = @'
digraph LyncVoicePolicies { 
    rankdir=LR;
    subgraph cluster_policy {
        color=lightgrey;
        node [shape=rectangle];
        Policy_Label [label="Policies",shape=none]
@@Policies@@
    }
    subgraph cluster_spacer1 {
        Spacer1_Label [label="                              ",shape=none]
        style=invis
    }
    subgraph cluster_usages {
        color=lightgrey;
        node [shape=rectangle];
        Usage_Label [label="PSTN Usages",shape=none]
@@PSTNUsages@@
    }
    subgraph cluster_spacer2 {
        Spacer2_Label [label="                              ",shape=none]
        style=invis
    }
    subgraph cluster_route {
        color=lightgrey;
        node [shape=rectangle];
        VoiceRoute_Label [label="Voice Routes",shape=none]
@@VoiceRoutes@@
    }
    subgraph cluster_spacer3 {
        Spacer3_Label [label="                              ",shape=none]
        style=invis
    }
    subgraph cluster_trunk {
        color=lightgrey;
        node [shape=rectangle];
        Trunk_Label [label="Trunks",shape=none]
@@Trunks@@
    }
    Policy_Label -> Spacer1_Label -> Usage_Label -> Spacer2_Label -> VoiceRoute_Label -> Spacer3_Label -> Trunk_Label[style=invis];

@@PolicyToPSTNUsage@@
    
@@PSTNUsageToVoiceRoute@@
    
@@VoiceRouteToTrunk@@
}
'@

# Create Policy Map
$PolicyMap = @{}
$Count = 0
$PolicyLabels = ''
(Get-CsVoicePolicy -Filter $PolicyFilter).Identity | Foreach {
    $PolicyName = $_ -replace 'tag:',''
    $PolicyMap."$($PolicyName)" = "Policy_$Count"
    $PolicyLabels += "        Policy_$Count [label=`"$($_)`"]`r`n"
    $Count++
}

# Create PSTN Usage Map
$PstnUsageMap = @{}
$Count = 0
$PstnUsageLabels = ''
(Get-CsPstnUsage).Usage | Foreach {
    $PstnUsageMap."$($_)" = "PstnUsage_$Count"
#    $PstnUsageLabels += "        PstnUsage_$Count [label=`"$($_)`"]`r`n"
    $Count++
}

# Create Voice Route Map
$VoiceRouteMap = @{}
$Count = 0
$VoiceRouteLabels = ''
(Get-CsVoiceRoute).Identity | Foreach {
    $VoiceRouteMap."$($_)" = "VoiceRoute_$Count"
#    $VoiceRouteLabels += "        VoiceRoute_$Count [label=`"$($_)`"]`r`n"
    $Count++
}

# Create pstn to route map
$PstnToRouteMap = @{}
$PstntoRouteMapArray = @()
Foreach ($Route in (Get-CSVoiceRoute)) {
    Foreach ($Usage in $Route.PSTNUsages) {
        $PstntoRouteMapArray += New-Object psobject -Property @{
            'PSTNUsage' = $Usage
            'Route' = $Route.Name
            'NumberPattern' = $Route.NumberPattern
            'RoutePriority' = $Route.Priority
        }
    }
}

# Create Trunk Map
$TrunkMap = @{}
$Count = 0
$TrunkLabels = ''
(Get-CsTrunk).Identity | Foreach {
    $TrunkMap."$($_)" = "Trunk_$Count"
    $TrunkName = $_ -replace 'PSTNGateway:',''
    $TrunkLabels += "        Trunk_$Count [label=`"$($TrunkName)`"]`r`n"
    $Count++
}

# Get our voice policy to usage table
$Policies = @()
$PolicyToPSTNUsageConnectors = ''
Foreach ($Policy in (Get-CsVoicePolicy -filter $PolicyFilter)) {
    $UsageOrder = 0
    $PolicyName = $Policy.Identity -replace 'tag:',''
    # create an array of objects tracking all the pstnusage assignment ordering
    ForEach ($Usage in $Policy.PSTNUsages) {
        $PolicyProps = @{
            'PolicyName' = $PolicyName
            'PSTNUsage' = $Usage
            'PSTNUsageOrder' = $UsageOrder
        }
        $Policies += New-Object psobject -Property $PolicyProps
        $PolicyToPSTNUsageConnectors += "    $($PolicyMap[`"$PolicyName`"]) -> $($PstnUsageMap[`"$Usage`"]) [constraint=false,label=$($UsageOrder)]`;`r`n"
        $UsageOrder++
    }
}

$VoiceRouteLabels = @()
$UsedPSTNUsages = @(($Policies | Select -Unique PSTNUsage).PSTNUsage)
ForEach ($Usage in $UsedPSTNUsages) {
    $PstnUsageLabels += "        $($PstnUsageMap[`"$Usage`"]) [label=`"$($Usage)`"]`r`n"
    $PstntoRouteMapArray | Where {$_.PSTNUsage -eq $Usage} | ForEach {
        $VoiceRouteLabels += "        $($VoiceRouteMap[`"$($_.Route)`"]) [label=`"$($_.Route)`"]`r`n"
    }
}

# Generate the graphviz diagram data
$GraphVisTemplate = $GraphVisTemplate -replace '@@Policies@@',$PolicyLabels
$GraphVisTemplate = $GraphVisTemplate -replace '@@PSTNUsages@@',$PstnUsageLabels
$GraphVisTemplate = $GraphVisTemplate -replace '@@VoiceRoutes@@',$VoiceRouteLabels
$GraphVisTemplate = $GraphVisTemplate -replace '@@Trunks@@',$TrunkLabels
$GraphVisTemplate = $GraphVisTemplate -replace '@@PolicyToPSTNUsage@@',$PolicyToPSTNUsageConnectors
$GraphVisTemplate = $GraphVisTemplate -replace '@@PSTNUsageToVoiceRoute@@',$PSTNUsageToVoiceRouteConnectors
$GraphVisTemplate = $GraphVisTemplate -replace '@@VoiceRouteToTrunk@@',$VoiceRouteToTrunkConnectors

## Get a list of PSTN usages that are mapped to routes (without a route they don't matter much anyway)
#$PstnUsages = @()
#$PstnUsageCount = 0
#ForEach ($Route in (Get-CsVoiceRoute)) {
#    Foreach ($Usage in ($Route.PSTNUsages)) {
#        $UsageProps = @{
#            'Route' = $Route.Name
#            'Pattern' = $Route.NumberPattern
#            'Gateways' = $Route.PstnGatewayList
#            'PSTNUsage' = $Usage
#            'UsageFieldTag' = "<f$UsageCount>"
#        }
#        New-Object psobject -Property $UsageProps
#        $UsageCount++
#    }
#}
# 
#
#
#$PoliciesList = ''
#$Policycount = 0
#$UniquePolicies = @(($Policies | Select -Unique PolicyName).PolicyName)
#Foreach ($Policy in $UniquePolicies) {
#    if ($Policycount -gt 0)
#    {
#        $PolicyList = "$PolicyList -> `"$Policy`""
#    }
#    else
#    {
#        $PolicyList = "`"$Policy`""
#    }
#    $Policycount++
#}
#$Output += "$PolicyList [style=invis];"
#$Output += @'
#
#}
#
#'@
 
# Uncomment the following to create a file to later convert into a graph with dot.exe 
$GraphVisTemplate | Out-File -Encoding ASCII $OutputFile
Write-Output "$OutputFile has been generated. Please feed this file into Graphviz to create a diagram"
#endregion Generate the graphviz diagram data
