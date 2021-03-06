﻿function Get-RemoteShareSessionInformation {
    <#
    .SYNOPSIS
       Get share session information from remote or local host.
    .DESCRIPTION
       Get share session information from remote or local host. Uses multiple runspaces if 
       multiple hosts are processed.
    .PARAMETER ComputerName
       Specifies the target computer for data query.
    .PARAMETER ThrottleLimit
       Specifies the maximum number of systems to inventory simultaneously 
    .PARAMETER Timeout
       Specifies the maximum time in second command can run in background before terminating this thread.
    .PARAMETER ShowProgress
       Show progress bar information

    .EXAMPLE
       PS > Get-RemoteShareSessionInformation

       <output>
       
       Description
       -----------
       <Placeholder>

    .NOTES
       Author: Zachary Loeber
       Site: http://www.the-little-things.net/
       Requires: Powershell 2.0

       Version History
       1.0.0 - 08/05/2013
        - Initial release
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias('DNSHostName','PSComputerName')]
        [string[]]$ComputerName=$env:computername,
       
        [Parameter()]
        [ValidateRange(1,65535)]
        [int32]$ThrottleLimit = 32,
 
        [Parameter()]
        [ValidateRange(1,65535)]
        [int32]$Timeout = 120,
 
        [Parameter()]
        [switch]$ShowProgress,
        
        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential = [System.Management.Automation.PSCredential]::Empty
    )

    begin {
        # Gather possible local host names and IPs to prevent credential utilization in some cases
        Write-Verbose -Message 'Share Information: Creating local hostname list'
        $IPAddresses = [net.dns]::GetHostAddresses($env:COMPUTERNAME) | Select-Object -ExpandProperty IpAddressToString
        $HostNames = $IPAddresses | ForEach-Object {
            try {
                [net.dns]::GetHostByAddress($_)
            } 
            catch {}
        } | Select-Object -ExpandProperty HostName -Unique
        $LocalHost = @('', '.', 'localhost', $env:COMPUTERNAME, '::1', '127.0.0.1') + $IPAddresses + $HostNames
 
        Write-Verbose -Message 'Share Session Information: Creating initial variables'
        $runspacetimers       = [HashTable]::Synchronized(@{})
        $runspaces            = New-Object -TypeName System.Collections.ArrayList
        $bgRunspaceCounter    = 0
        
        Write-Verbose -Message 'Share Session Information: Creating Initial Session State'
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        foreach ($ExternalVariable in ('runspacetimers', 'Credential', 'LocalHost'))
        {
            Write-Verbose -Message "Share Session Information: Adding variable $ExternalVariable to initial session state"
            $iss.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $ExternalVariable, (Get-Variable -Name $ExternalVariable -ValueOnly), ''))
        }
        
        Write-Verbose -Message 'Share Session Information: Creating runspace pool'
        $rp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $iss, $Host)
        $rp.ApartmentState = 'STA'
        $rp.Open()
 
        # This is the actual code called for each computer
        Write-Verbose -Message 'Share Session Information: Defining background runspaces scriptblock'
        $ScriptBlock = {
            [CmdletBinding()]
            param (
                [Parameter(Position=0)]
                [string]$ComputerName,
 
                [Parameter(Position=1)]
                [int]$bgRunspaceID
            )
            $runspacetimers.$bgRunspaceID = Get-Date
            
            try {
                Write-Verbose -Message ('Share Session Information: Runspace {0}: Start' -f $ComputerName)
                $WMIHast = @{
                    ComputerName = $ComputerName
                    ErrorAction = 'Stop'
                }
                if (($LocalHost -notcontains $ComputerName) -and ($Credential -ne [System.Management.Automation.PSCredential]::Empty))
                {
                    $WMIHast.Credential = $Credential
                }

                # General variables
                $ResultSet = @()
                $PSDateTime = Get-Date
                
                #region ShareSessions
                Write-Verbose -Message ('Share Session Information: Runspace {0}: Share session information' -f $ComputerName)

                # Modify this variable to change your default set of display properties
                $defaultProperties    = @('ComputerName','Sessions')                                          
                $WMI_ConnectionProps  = @('ShareName','UserName','RemoteComputerName')
                $SessionData = @()
                $wmi_connections = Get-WmiObject @WMIHast -Class Win32_ServerConnection | select $WMI_ConnectionProps
                foreach ($userSession in $wmi_connections)
                {
                    $SessionProperty = @{
                        'ShareName' = $userSession.ShareName
                        'UserName' = $userSession.UserName
                        'RemoteComputerName' = $userSession.ComputerName
                    }
                    $SessionData += New-Object -TypeName PSObject -Property $SessionProperty
                }
             
                $ResultProperty = @{
                    'PSComputerName' = $ComputerName
                    'PSDateTime' = $PSDateTime
                    'ComputerName' = $ComputerName
                    'Sessions' = $SessionData
                }

                $ResultObject = New-Object -TypeName PSObject -Property $ResultProperty
                # Setup the default properties for output
                $ResultObject.PSObject.TypeNames.Insert(0,'My.ShareSession.Info')
                $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$defaultProperties)
                $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
                $ResultObject | Add-Member MemberSet PSStandardMembers $PSStandardMembers
                
                $ResultSet += $ResultObject

                #endregion ShareSessions

                Write-Output -InputObject $ResultSet
            }
            catch {
                Write-Warning -Message ('Share Session Information: {0}: {1}' -f $ComputerName, $_.Exception.Message)
            }
            Write-Verbose -Message ('Share Session Information: Runspace {0}: End' -f $ComputerName)
        }
 
        function Get-Result {
            [CmdletBinding()]
            param (
                [switch]$Wait
            )
            do {
                $More = $false
                foreach ($runspace in $runspaces)
                {
                    $StartTime = $runspacetimers[$runspace.ID]
                    if ($runspace.Handle.isCompleted)
                    {
                        Write-Verbose -Message ('Share Session Information: Thread done for {0}' -f $runspace.IObject)
                        $runspace.PowerShell.EndInvoke($runspace.Handle)
                        $runspace.PowerShell.Dispose()
                        $runspace.PowerShell = $null
                        $runspace.Handle = $null
                    }
                    elseif ($runspace.Handle -ne $null)
                    {
                        $More = $true
                    }
                    if ($Timeout -and $StartTime)
                    {
                        if ((New-TimeSpan -Start $StartTime).TotalSeconds -ge $Timeout -and $runspace.PowerShell)
                        {
                            Write-Warning -Message ('Share Session Information: Timeout {0}' -f $runspace.IObject)
                            $runspace.PowerShell.Dispose()
                            $runspace.PowerShell = $null
                            $runspace.Handle = $null
                        }
                    }
                }
                if ($More -and $PSBoundParameters['Wait'])
                {
                    Start-Sleep -Milliseconds 100
                }
                foreach ($threat in $runspaces.Clone())
                {
                    if ( -not $threat.handle)
                    {
                        Write-Verbose -Message ('Share Session Information: Removing {0} from runspaces' -f $threat.IObject)
                        $runspaces.Remove($threat)
                    }
                }
                if ($ShowProgress)
                {
                    $ProgressSplatting = @{
                        Activity = 'Getting share session information'
                        Status = 'Share Session Information: {0} of {1} total threads done' -f ($bgRunspaceCounter - $runspaces.Count), $bgRunspaceCounter
                        PercentComplete = ($bgRunspaceCounter - $runspaces.Count) / $bgRunspaceCounter * 100
                    }
                    Write-Progress @ProgressSplatting
                }
            }
            while ($More -and $PSBoundParameters['Wait'])
        }
    }
    process {
        foreach ($Computer in $ComputerName)
        {
            $bgRunspaceCounter++
            $psCMD = [System.Management.Automation.PowerShell]::Create().AddScript($ScriptBlock)
            $null = $psCMD.AddParameter('bgRunspaceID',$bgRunspaceCounter)
            $null = $psCMD.AddParameter('ComputerName',$Computer)
            $null = $psCMD.AddParameter('Verbose',$VerbosePreference)
            $psCMD.RunspacePool = $rp
 
            Write-Verbose -Message ('Share Session Information: Starting {0}' -f $Computer)
            [void]$runspaces.Add(@{
                Handle = $psCMD.BeginInvoke()
                PowerShell = $psCMD
                IObject = $Computer
                ID = $bgRunspaceCounter
           })
           Get-Result
        }
    }
    end {
        Get-Result -Wait
        if ($ShowProgress)
        {
            Write-Progress -Activity 'Share Session Information: Getting share session information' -Status 'Done' -Completed
        }
        Write-Verbose -Message "Share Session Information: Closing runspace pool"
        $rp.Close()
        $rp.Dispose()
    }
}
