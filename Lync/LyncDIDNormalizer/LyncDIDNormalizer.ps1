#region Pre-Process
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $CommandLine = $MyInvocation.Line.Replace($MyInvocation.InvocationName, $MyInvocation.MyCommand.Definition)
    Write-Warning 'Script is not running in STA Apartment State.'
    Write-Warning '  Attempting to restart this script with the -Sta flag.....'
    Write-Verbose "  Script: $CommandLine"
    Start-Process -FilePath PowerShell.exe -ArgumentList "$CommandLine -Sta"
    exit
}
#endregion

#region Functions
### General Use Functions ###
function New-Popup {
    param (
        [Parameter(Position=0,Mandatory=$True,HelpMessage="Enter a message for the popup")]
        [ValidateNotNullorEmpty()]
        [string]$Message,
        [Parameter(Position=1,Mandatory=$True,HelpMessage="Enter a title for the popup")]
        [ValidateNotNullorEmpty()]
        [string]$Title,
        [Parameter(Position=2,HelpMessage="How many seconds to display? Use 0 require a button click.")]
        [ValidateScript({$_ -ge 0})]
        [int]$Time=0,
        [Parameter(Position=3,HelpMessage="Enter a button group")]
        [ValidateNotNullorEmpty()]
        [ValidateSet("OK","OKCancel","AbortRetryIgnore","YesNo","YesNoCancel","RetryCancel")]
        [string]$Buttons="OK",
        [Parameter(Position=4,HelpMessage="Enter an icon set")]
        [ValidateNotNullorEmpty()]
        [ValidateSet("Stop","Question","Exclamation","Information" )]
        [string]$Icon="Information"
    )

    #convert buttons to their integer equivalents
    switch ($Buttons) {
        "OK"               {$ButtonValue = 0}
        "OKCancel"         {$ButtonValue = 1}
        "AbortRetryIgnore" {$ButtonValue = 2}
        "YesNo"            {$ButtonValue = 4}
        "YesNoCancel"      {$ButtonValue = 3}
        "RetryCancel"      {$ButtonValue = 5}
    }

    #set an integer value for Icon type
    switch ($Icon) {
        "Stop"        {$iconValue = 16}
        "Question"    {$iconValue = 32}
        "Exclamation" {$iconValue = 48}
        "Information" {$iconValue = 64}
    }

    #create the COM Object
    Try {
        $wshell = New-Object -ComObject Wscript.Shell -ErrorAction Stop
        #Button and icon type values are added together to create an integer value
        $wshell.Popup($Message,$Time,$Title,$ButtonValue+$iconValue)
    }
    Catch {
        Write-Warning "Failed to create Wscript.Shell COM object"
        Write-Warning $_.exception.message
    }
}

function Set-ClipBoard{
  param(
    [string]$text
  )
  process{
    Add-Type -AssemblyName System.Windows.Forms
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.Text = $text
    $tb.SelectAll()
    $tb.Copy()
  }
}

function Get-FileFromDialog {
    # Example: 
    #  $fileName = Get-FileFromDialog -fileFilter 'CSV file (*.csv)|*.csv' -titleDialog "Select A CSV File:"
    [CmdletBinding()] 
    param (
        [Parameter(Position=0)]
        [string]$initialDirectory = './',
        [Parameter(Position=1)]
        [string]$fileFilter = 'All files (*.*)| *.*',
        [Parameter(Position=2)] 
        [string]$titleDialog = '',
        [Parameter(Position=3)] 
        [switch]$AllowMultiSelect=$false
    )
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = $fileFilter
    $OpenFileDialog.Title = $titleDialog
    $OpenFileDialog.ShowHelp = if ($Host.name -eq 'ConsoleHost') {$true} else {$false}
    if ($AllowMultiSelect) { $openFileDialog.MultiSelect = $true } 
    $OpenFileDialog.ShowDialog() | Out-Null
    if ($AllowMultiSelect) { return $openFileDialog.Filenames } else { return $openFileDialog.Filename }
}

function Save-FileFromDialog {
    # Example: 
    #  $fileName = Save-FileFromDialog -defaultfilename 'backup.csv' -titleDialog 'Backup to a CSV file:'
    [CmdletBinding()] 
    param (
        [Parameter(Position=0)]
        [string]$initialDirectory = './',
        [Parameter(Position=1)]
        [string]$defaultfilename = '',
        [Parameter(Position=2)]
        [string]$fileFilter = 'All files (*.*)| *.*',
        [Parameter(Position=3)] 
        [string]$titleDialog = ''
    )
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $SetBackupLocation = New-Object System.Windows.Forms.SaveFileDialog
    $SetBackupLocation.initialDirectory = $initialDirectory
    $SetBackupLocation.filter = $fileFilter
    $SetBackupLocation.FilterIndex = 2
    $SetBackupLocation.Title = $titleDialog
    $SetBackupLocation.RestoreDirectory = $true
    $SetBackupLocation.ShowHelp = if ($Host.name -eq 'ConsoleHost') {$true} else {$false}
    $SetBackupLocation.filename = $defaultfilename
    $SetBackupLocation.ShowDialog() | Out-Null
    return $SetBackupLocation.Filename
}

function Add-Array2Clipboard {
  param (
    [PSObject[]]$ConvertObject,
    [switch]$Header
  )
  process{
    $array = @()

    if ($Header) {
      $line =""
      $ConvertObject | Get-Member -MemberType Property,NoteProperty,CodeProperty | Select -Property Name | %{
        $line += ($_.Name.tostring() + "`t")
      }
      $array += ($line.TrimEnd("`t") + "`r")
    }
    foreach($row in $ConvertObject){
        $line =""
        $row | Get-Member -MemberType Property,NoteProperty | %{
          $Name = $_.Name
          if(!$Row.$Name){$Row.$Name = ""}
          $line += ([string]$Row.$Name + "`t")
        }
        $array += ($line.TrimEnd("`t") + "`r")
    }
    Set-ClipBoard $array
  }
}

function Select-Unique {
    # Select objects based on unique property
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string[]] $Property,
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        $InputObject,
        [Parameter()]
        [switch] $AsHashtable,
        [Parameter()]
        [switch] $NoElement
    )
 
    begin {
        $Keys = @{}
    }
 
    process {
        $InputObject | foreach-object {
            $o = $_
            $k = $Property | foreach-object -begin {
                    $s = ''
                } -process {
                    # Delimit multiple properties like group-object does.
                    if ( $s.Length -gt 0 ) {
                        $s += ', '
                    }
 
                    $s += $o.$_ -as [string]
                } -end {
                    $s
                }
 
            if ( -not $Keys.ContainsKey($k) ) {
                $Keys.Add($k, $null)
                if ( -not $AsHashtable ) {
                    $o
                }
                elseif ( -not $NoElement ) {
                    $Keys[$k] = $o
                }
            }
        }
    }
 
    end {
        if ( $AsHashtable ) {
            $Keys
        }
    }
}

function Get-OUDialog {
    <#
    .SYNOPSIS
    A self contained WPF/XAML treeview organizational unit selection dialog box.
    .DESCRIPTION
    A self contained WPF/XAML treeview organizational unit selection dialog box. No AD modules required, just need to be joined to the domain.
    .EXAMPLE
    $OU = Get-OUDialog
    .NOTES
    Author: Zachary Loeber
    Requires: Powershell 4.0
    Version History
    1.0.0 - 03/21/2015
        - Initial release (the function is a bit overbloated because I'm simply embedding some of my prior functions directly
          in the thing instead of customizing the code for the function. Meh, it gets the job done...
    .LINK
    https://github.com/zloeber/Powershell/blob/master/ActiveDirectory/Select-OU/Get-OUDialog.ps1
    .LINK
    http://www.the-little-things.net
    #>
    [CmdletBinding()]
    param()
    
    function Get-ChildOUStructure {
        <#
        .SYNOPSIS
        Create JSON exportable tree view of AD OU (or other) structures.
        .DESCRIPTION
        Create JSON exportable tree view of AD OU (or other) structures in Canonical Name format.
        .PARAMETER ouarray
        Array of OUs in CanonicalName format (ie. domain/ou1/ou2)
        .PARAMETER oubase
        Base of OU
        .EXAMPLE
        $OUs = @(Get-ADObject -Filter {(ObjectClass -eq "OrganizationalUnit")} -Properties CanonicalName).CanonicalName
        $test = $OUs | Get-ChildOUStructure | ConvertTo-Json -Depth 20
        .NOTES
        Author: Zachary Loeber
        Requires: Powershell 3.0, Lync
        Version History
        1.0.0 - 12/24/2014
            - Initial release
        .LINK
        https://github.com/zloeber/Powershell/blob/master/ActiveDirectory/Get-ChildOUStructure.ps1
        .LINK
        http://www.the-little-things.net
        #>
        [CmdletBinding()]
        param(
            [Parameter(Position=0, ValueFromPipeline=$true, Mandatory=$true, HelpMessage='Array of OUs in CanonicalName formate (ie. domain/ou1/ou2)')]
            [string[]]$ouarray,
            [Parameter(Position=1, HelpMessage='Base of OU.')]
            [string]$oubase = ''
        )
        begin {
            $newarray = @()
            $base = ''
            $firstset = $false
            $ouarraylist = @()
        }
        process {
            $ouarraylist += $ouarray
        }
        end {
            $ouarraylist = $ouarraylist | Where {($_ -ne $null) -and ($_ -ne '')} | Select -Unique | Sort-Object
            if ($ouarraylist.count -gt 0) {
                $ouarraylist | Foreach {
                   # $prioroupath = if ($oubase -ne '') {$oubase + '/' + $_} else {''}
                    $firstelement = @($_ -split '/')[0]
                    $regex = "`^`($firstelement`?`)"
                    $tmp = $_ -replace $regex,'' -replace "^(\/?)",''

                    if (-not $firstset) {
                        $base = $firstelement
                        $firstset = $true
                    }
                    else {
                        if (($base -ne $firstelement) -or ($tmp -eq '')) {
                            Write-Verbose "Processing Subtree for: $base"
                            $fulloupath = if ($oubase -ne '') {$oubase + '/' + $base} else {$base}
                            New-Object psobject -Property @{
                                'name' = $base
                                'path' = $fulloupath
                                'children' = if ($newarray.Count -gt 0) {,@(Get-ChildOUStructure -ouarray $newarray -oubase $fulloupath)} else {$null}
                            }
                            $base = $firstelement
                            $newarray = @()
                            $firstset = $false
                        }
                    }
                    if ($tmp -ne '') {
                        $newarray += $tmp
                    }
                }
                Write-Verbose "Processing Subtree for: $base"
                $fulloupath = if ($oubase -ne '') {$oubase + '/' + $base} else {$base}
                New-Object psobject -Property @{
                    'name' = $base
                    'path' = $fulloupath
                    'children' = if ($newarray.Count -gt 0) {,@(Get-ChildOUStructure -ouarray $newarray -oubase $fulloupath)} else {$null}
                }
            }
        }
    }
    
    function Convert-CNToDN {
        param([string]$CN)
        $SplitCN = $CN -split '/'
        if ($SplitCN.Count -eq 1) {
            return 'DC=' + (($SplitCN)[0] -replace '\.',',DC=')
        }
        else {
            $basedn = '.'+($SplitCN)[0] -replace '\.',',DC='
            [array]::Reverse($SplitCN)
            $ous = ''
            for ($index = 0; $index -lt ($SplitCN.count - 1); $index++) {
                $ous += 'OU=' + $SplitCN[$index] + ','
            }
            $result = ($ous + $basedn) -replace ',,',','
            return $result
        }
    }

    function Add-TreeItem {
        param(
              $TreeObj,
              $Name,
              $Parent,
              $Tag
              )

        $ChildItem = New-Object System.Windows.Controls.TreeViewItem
        $ChildItem.Header = $Name
        $ChildItem.Tag = $Tag
        $Parent.Items.Add($ChildItem) | Out-Null

        if (($TreeObj.children).Count -gt 0) {
            foreach ($ou in $TreeObj.children) {
                $treeparent = Add-TreeItem -TreeObj $ou -Name $ou.Name -Parent $ChildItem -Tag $ou.path
            }
        }
    }

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {               
        Write-Warning 'Run PowerShell.exe with -Sta switch, then run this script.'
        Write-Warning 'Example:'
        Write-Warning '    PowerShell.exe -noprofile -Sta'
        break
    }

    [void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
    [xml]$xamlMain = @'
<Window x:Name="windowSelectOU"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select OU" Height="350" Width="525">
    <Grid>
        <TreeView x:Name="treeviewOUs" Margin="10,10,10.4,33.8"/>
        <Button x:Name="btnCancel" Content="Cancel" Margin="0,0,10.4,5.8" ToolTip="Filter" Height="23" VerticalAlignment="Bottom" HorizontalAlignment="Right" Width="71" IsCancel="True"/>
        <Button x:Name="btnSelect" Content="Select" Margin="0,0,86.4,5.8" ToolTip="Filter" HorizontalAlignment="Right" Width="71" Height="23" VerticalAlignment="Bottom" IsDefault="True"/>
        <TextBlock x:Name="txtSelectedOU" Margin="10,0,162.4,5.8" TextWrapping="Wrap" VerticalAlignment="Bottom" Height="23" Background="{DynamicResource {x:Static SystemColors.ControlBrushKey}}" IsEnabled="False"/>
    </Grid>
</Window>
'@

    # Read XAML
    $reader=(New-Object System.Xml.XmlNodeReader $xamlMain) 
    $window=[Windows.Markup.XamlReader]::Load( $reader )

    $namespace = @{ x = 'http://schemas.microsoft.com/winfx/2006/xaml' }
    $xpath_formobjects = "//*[@*[contains(translate(name(.),'n','N'),'Name')]]" 

    # Create a variable for every named xaml element
    Select-Xml $xamlMain -Namespace $namespace -xpath $xpath_formobjects | Foreach {
        $_.Node | Foreach {
            Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name)
        }
    }

    $conn = Connect-ActiveDirectory -ADContextType:DirectoryEntry
    $domstruct = @(Search-AD -DirectoryEntry $conn -Filter '(ObjectClass=organizationalUnit)' -Properties CanonicalName).CanonicalName | sort | Get-ChildOUStructure

    Add-TreeItem -TreeObj $domstruct -Name $domstruct.Name -Parent $treeviewOUs -Tag $domstruct.path

    $treeviewOUs.add_SelectedItemChanged({
        $txtSelectedOU.Text = Convert-CNToDN $this.SelectedItem.Tag
    })

    $btnSelect.add_Click({
        $script:DialogResult = $txtSelectedOU.Text
        $windowSelectOU.Close()
    })
    $btnCancel.add_Click({
        $script:DialogResult = $null
    })

    # Due to some bizarre bug with showdialog and xaml we need to invoke this asynchronously 
    #  to prevent a segfault
    $async = $windowSelectOU.Dispatcher.InvokeAsync({
        $retval = $windowSelectOU.ShowDialog()
    })
    $async.Wait() | Out-Null

    # Clear out previously created variables for every named xaml element to be nice...
    Select-Xml $xamlMain -Namespace $namespace -xpath $xpath_formobjects | Foreach {
        $_.Node | Foreach {
            Remove-Variable -Name ($_.Name)
        }
    }
    return $DialogResult
}

function Connect-ActiveDirectory {
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName='Credential')]
        [Parameter(ParameterSetName='CredentialObject')]
        [Parameter(ParameterSetName='Default')]
        [string]$ComputerName,
        
        [Parameter(ParameterSetName='Credential')]
        [string]$DomainName,
        
        [Parameter(ParameterSetName='Credential', Mandatory=$true)]
        [string]$UserName,
        
        [Parameter(ParameterSetName='Credential', HelpMessage='Password for Username in remote domain.', Mandatory=$true)]
        [string]$Password,
        
        [parameter(ParameterSetName='CredentialObject',HelpMessage='Full credential object',Mandatory=$True)]
        [System.Management.Automation.PSCredential]$Creds,
        
        [Parameter(HelpMessage='Context to return, forest, domain, or DirectoryEntry.')]
        [ValidateSet('Domain','Forest','DirectoryEntry','ADContext')]
        [string]$ADContextType = 'ADContext'
    )
    
    $UsingAltCred = $false
    
    # If the username was passed in domain\<username> or username@domain then gank the domain name for later use
    if (($UserName -split "\\").Count -gt 1) {
        $DomainName = ($UserName -split "\\")[0]
        $UserName = ($UserName -split "\\")[1]
    }
    if (($UserName -split "\@").Count -gt 1) {
        $DomainName = ($UserName -split "\@")[1]
        $UserName = ($UserName -split "\@")[0]
    }
    
    switch ($PSCmdlet.ParameterSetName) {
        'CredentialObject' {
            if ($Creds.GetNetworkCredential().Domain -ne '')  {
                $UserName= $Creds.GetNetworkCredential().UserName
                $Password = $Creds.GetNetworkCredential().Password
                $DomainName = $Creds.GetNetworkCredential().Domain
                $UsingAltCred = $true
            }
            else {
                throw 'The credential object must include a defined domain.'
            }
        }
        'Credential' {
            if (-not $DomainName) {
                Write-Error 'Username must be in @domainname.com or <domainname>\<username> format or the domain name must be manually passed in the DomainName parameter'
                return $null
            }
            else {
                $UserName = $DomainName + '\' + $UserName
                $UsingAltCred = $true
            }
        }
    }

    $ADServer = ''
    
    # If a computer name was specified then we will attempt to perform a remote connection
    if ($ComputerName) {
        # If a computername was specified then we are connecting remotely
        $ADServer = "LDAP://$($ComputerName)"
        $ContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContextType]::DirectoryServer

        if ($UsingAltCred) {
            $ADContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext $ContextType, $ComputerName, $UserName, $Password
        }
        else {
            if ($ComputerName) {
                $ADContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext $ContextType, $ComputerName
            }
            else {
                $ADContext = New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext $ContextType
            }
        }
        
        try {
            switch ($ADContextType) {
                'ADContext' {
                    return $ADContext
                }
                'DirectoryEntry' {
                    if ($UsingAltCred) {
                        return New-Object System.DirectoryServices.DirectoryEntry($ADServer ,$UserName, $Password)
                    }
                    else {
                        return New-Object -TypeName System.DirectoryServices.DirectoryEntry $ADServer
                    }
                }
                'Forest' {
                    return [System.DirectoryServices.ActiveDirectory.Forest]::GetForest($ADContext)
                }
                'Domain' {
                    return [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain($ADContext)
                }
            }
        }
        catch {
            throw
        }
    }
    
    # If using just an alternate credential without specifying a remote computer (dc) to connect they
    # try connecting to the locally joined domain with the credentials.
    if ($UsingAltCred) {
        # *** FINISH ME ***
    }
    # We have not specified another computer or credential so connect to the local domain if possible.
    try {
        $ContextType = [System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain
    }
    catch {
        throw 'Unable to connect to a default domain. Is this a domain joined account?'
    }
    try {
        switch ($ADContextType) {
            'ADContext' {
                return New-Object System.DirectoryServices.ActiveDirectory.DirectoryContext $ContextType
            }
            'DirectoryEntry' {
                return [System.DirectoryServices.DirectoryEntry]''
            }
            'Forest' {
                return [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
            }
            'Domain' {
                return [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
            }
        }
    }
    catch {
        throw
    }
}

function Search-AD {
    # Original Author (largely unmodified btw): 
    #  http://becomelotr.wordpress.com/2012/11/02/quick-active-directory-search-with-pure-powershell/
    [CmdletBinding()]
    param (
        [string[]]$Filter,
        [string[]]$Properties = @('Name','ADSPath'),
        [string]$SearchRoot='',
        [switch]$DontJoinAttributeValues,
        [System.DirectoryServices.DirectoryEntry]$DirectoryEntry = $null
    )

    if ($DirectoryEntry -ne $null) {
        if ($SearchRoot -ne '') {
            $DirectoryEntry.set_Path($SearchRoot)
        }
    }
    else {
        $DirectoryEntry = [System.DirectoryServices.DirectoryEntry]$SearchRoot
    }

    if ($Filter) {
        $LDAP = "(&({0}))" -f ($Filter -join ')(')
    }
    else {
        $LDAP = "(name=*)"
    }
    try {
        (New-Object System.DirectoryServices.DirectorySearcher -ArgumentList @(
            $DirectoryEntry,
            $LDAP,
            $Properties
        ) -Property @{
            PageSize = 1000
        }).FindAll() | ForEach-Object {
            $ObjectProps = @{}
            $_.Properties.GetEnumerator() |
                Foreach-Object {
                    $Val = @($_.Value)
                    if ($_.Name -ne $null) {
                        if ($DontJoinAttributeValues -and ($Val.Count -gt 1)) {
                            $ObjectProps.Add($_.Name,$_.Value)
                        }
                        else {
                            $ObjectProps.Add($_.Name,(-join $_.Value))
                        }
                    }
                }
            if ($ObjectProps.psbase.keys.count -ge 1) {
                New-Object PSObject -Property $ObjectProps | Select $Properties
            }
        }
    }
    catch {
        Write-Warning -Message ('Search-AD: Filter - {0}: Root - {1}: Error - {2}' -f $LDAP,$Root.Path,$_.Exception.Message)
    }
}

function Format-LyncADAccount {
    [cmdletbinding()]
    param(
        [Parameter(HelpMessage='User or users to process.', Mandatory=$true, ValueFromPipeline=$true)]
        [psobject]$User,
        [Parameter(HelpMessage='Type of account.')]
        [string]$PhoneType = ''
    )
    begin {}
    process {
        $userinfo = @{
            UserName = $User.Name
            UserLogin = $User.SamAccountName
            SID = $User.SID
            dn = $User.distinguishedName
            Enabled = $null
            SIPAddress = $User.'msrtcsip-primaryuseraddress'
            PhoneType = ''
            LyncEnabled = $null
            UMEnabled = $null
            OU = $User.distinguishedName -replace "$(($User.distinguishedName -split ',')[0]),",''
            Extension = $null
            email = $User.mail
            DID = $null
            DDI = $null
            PrivateDID = $null
            ADPhoneNumber = $User.telephoneNumber
            department = $User.department
            office = $User.physicalDeliveryOfficeName
            Notes = ''
        }
        if ($User.useraccountcontrol -ne $null) {
            $userinfo.Enabled = -not (Convert-ADUserAccountControl $User.useraccountcontrol).ACCOUNTDISABLE
        }
        $userinfo.LyncEnabled = if ($User.'msRTCSIP-UserEnabled') {$true} else {$false}
        $userinfo.UMEnabled = if ($User.msExchUMEnabledFlags -ne $null) {$true} else {$false}
        $userinfo.Extension = if ($User.'msRTCSIP-Line' -match '^.*ext=(.*)$') {$matches[1]}
        $userinfo.DID = if ($User.'msRTCSIP-Line' -ne $null) {$User.'msRTCSIP-Line'}
        $userinfo.DDI = if ($User.'msRTCSIP-Line' -match '^tel:\+*(.*).*$') {$Matches[1]} `
        $userinfo.PrivateDID = if ($User.'msRTCSIP-PrivateLine' -ne $null) {$User.'msRTCSIP-PrivateLine'}
        switch ($User.'msrtcsip-ownerurn') {
            'urn:application:Caa' {
                $userinfo.PhoneType = 'DialIn Conferencing'
            }
            'msrtcsip-ownerurn' {
                $userinfo.PhoneType = 'RGS Workflow'
            }
            'urn:device:commonareaphone' {
                $userinfo.PhoneType = 'Common Area'
            }
            
            default {
                $userinfo.PhoneType = $PhoneType
            }
        }

        New-Object psobject -Property $userinfo
    }
    end {}
}

function Convert-ADUserAccountControl {
    <#
        author: Zachary Loeber
        http://support.microsoft.com/kb/305144
        http://msdn.microsoft.com/en-us/library/cc245514.aspx
        
        Takes the useraccesscontrol property, evaluates it, and spits out an object with all set UAC properties
    #>
    [cmdletbinding()]
    param(
        [Parameter(HelpMessage='User or users to process.', Mandatory=$true, ValueFromPipeline=$true)]
        [string]$UACProperty
    )

    Add-Type -TypeDefinition @"
    [System.Flags]
    public enum userAccountControlFlags {
        SCRIPT                                  = 0x0000001,
        ACCOUNTDISABLE                          = 0x0000002,
        NOT_USED                                = 0x0000004,
        HOMEDIR_REQUIRED                        = 0x0000008,
        LOCKOUT                                 = 0x0000010,
        PASSWD_NOTREQD                          = 0x0000020,
        PASSWD_CANT_CHANGE                      = 0x0000040,
        ENCRYPTED_TEXT_PASSWORD_ALLOWED         = 0x0000080,
        TEMP_DUPLICATE_ACCOUNT                  = 0x0000100,
        NORMAL_ACCOUNT                          = 0x0000200,
        INTERDOMAIN_TRUST_ACCOUNT               = 0x0000800,
        WORKSTATION_TRUST_ACCOUNT               = 0x0001000,
        SERVER_TRUST_ACCOUNT                    = 0x0002000,
        DONT_EXPIRE_PASSWD                      = 0x0010000,
        MNS_LOGON_ACCOUNT                       = 0x0020000,
        SMARTCARD_REQUIRED                      = 0x0040000,
        TRUSTED_FOR_DELEGATION                  = 0x0080000,
        NOT_DELEGATED                           = 0x0100000,
        USE_DES_KEY_ONLY                        = 0x0200000,
        DONT_REQUIRE_PREAUTH                    = 0x0400000,
        PASSWORD_EXPIRED                        = 0x0800000,
        TRUSTED_TO_AUTH_FOR_DELEGATION          = 0x1000000
    }
"@
    $UACAttribs = @(
        'SCRIPT',
        'ACCOUNTDISABLE',
        'NOT_USED',
        'HOMEDIR_REQUIRED',
        'LOCKOUT',
        'PASSWD_NOTREQD',
        'PASSWD_CANT_CHANGE',
        'ENCRYPTED_TEXT_PASSWORD_ALLOWED',
        'TEMP_DUPLICATE_ACCOUNT',
        'NORMAL_ACCOUNT',
        'INTERDOMAIN_TRUST_ACCOUNT',
        'WORKSTATION_TRUST_ACCOUNT',
        'SERVER_TRUST_ACCOUNT',
        'DONT_EXPIRE_PASSWD',
        'MNS_LOGON_ACCOUNT',
        'SMARTCARD_REQUIRED',
        'TRUSTED_FOR_DELEGATION',
        'NOT_DELEGATED',
        'USE_DES_KEY_ONLY',
        'DONT_REQUIRE_PREAUTH',
        'PASSWORD_EXPIRED',
        'TRUSTED_TO_AUTH_FOR_DELEGATION',
        'PARTIAL_SECRETS_ACCOUNT'
    )

    try {
        Write-Verbose ('Convert-ADUserAccountControl: Converting UAC.')
        $UACOutput = New-Object psobject
        $UAC = [Enum]::Parse('userAccountControlFlags', $UACProperty)
        $UACAttribs | Foreach {
            Add-Member -InputObject $UACOutput -MemberType NoteProperty -Name $_ -Value ($UAC -match $_) -Force
        }
        Write-Output $UACOutput
    }
    catch {
        Write-Warning -Message ('Convert-ADUserAccountControl: {0}' -f $_.Exception.Message)
    }
}

function Append-ADUserAccountControl {
    <#
        author: Zachary Loeber
        http://support.microsoft.com/kb/305144
        http://msdn.microsoft.com/en-us/library/cc245514.aspx
        
        Takes an object containing the useraccesscontrol property, evaluates it, and appends all set UAC properties
    #>
    [cmdletbinding()]
    param(
        [Parameter(HelpMessage='User or users to process.', Mandatory=$true, ValueFromPipeline=$true)]
        [psobject[]]$User
    )

    begin {
        Add-Type -TypeDefinition @" 
        [System.Flags]
        public enum userAccountControlFlags {
            SCRIPT                                  = 0x0000001,
            ACCOUNTDISABLE                          = 0x0000002,
            NOT_USED                                = 0x0000004,
            HOMEDIR_REQUIRED                        = 0x0000008,
            LOCKOUT                                 = 0x0000010,
            PASSWD_NOTREQD                          = 0x0000020,
            PASSWD_CANT_CHANGE                      = 0x0000040,
            ENCRYPTED_TEXT_PASSWORD_ALLOWED         = 0x0000080,
            TEMP_DUPLICATE_ACCOUNT                  = 0x0000100,
            NORMAL_ACCOUNT                          = 0x0000200,
            INTERDOMAIN_TRUST_ACCOUNT               = 0x0000800,
            WORKSTATION_TRUST_ACCOUNT               = 0x0001000,
            SERVER_TRUST_ACCOUNT                    = 0x0002000,
            DONT_EXPIRE_PASSWD                      = 0x0010000,
            MNS_LOGON_ACCOUNT                       = 0x0020000,
            SMARTCARD_REQUIRED                      = 0x0040000,
            TRUSTED_FOR_DELEGATION                  = 0x0080000,
            NOT_DELEGATED                           = 0x0100000,
            USE_DES_KEY_ONLY                        = 0x0200000,
            DONT_REQUIRE_PREAUTH                    = 0x0400000,
            PASSWORD_EXPIRED                        = 0x0800000,
            TRUSTED_TO_AUTH_FOR_DELEGATION          = 0x1000000
        }
"@
        $Users = @()
        $UACAttribs = @(
            'SCRIPT',
            'ACCOUNTDISABLE',
            'NOT_USED',
            'HOMEDIR_REQUIRED',
            'LOCKOUT',
            'PASSWD_NOTREQD',
            'PASSWD_CANT_CHANGE',
            'ENCRYPTED_TEXT_PASSWORD_ALLOWED',
            'TEMP_DUPLICATE_ACCOUNT',
            'NORMAL_ACCOUNT',
            'INTERDOMAIN_TRUST_ACCOUNT',
            'WORKSTATION_TRUST_ACCOUNT',
            'SERVER_TRUST_ACCOUNT',
            'DONT_EXPIRE_PASSWD',
            'MNS_LOGON_ACCOUNT',
            'SMARTCARD_REQUIRED',
            'TRUSTED_FOR_DELEGATION',
            'NOT_DELEGATED',
            'USE_DES_KEY_ONLY',
            'DONT_REQUIRE_PREAUTH',
            'PASSWORD_EXPIRED',
            'TRUSTED_TO_AUTH_FOR_DELEGATION',
            'PARTIAL_SECRETS_ACCOUNT'
        )
    }
    process {
        $Users += $User
    }
    end {
        foreach ($usr in $Users) {
            if ($usr.PSObject.Properties.Match('useraccountcontrol').Count) {
                try {
                    Write-Verbose ('Append-ADUserAccountControl: Found useraccountcontrol property, enumerating.')
                    $UAC = [Enum]::Parse('userAccountControlFlags', $usr.useraccountcontrol)
                    $UACAttribs | Foreach {
                        Add-Member -InputObject $usr -MemberType NoteProperty -Name $_ -Value ($UAC -match $_) -Force
                    }
                    Write-Output $usr
                }
                catch {
                    Write-Warning -Message ('Append-ADUserAccountControl: {0}' -f $_.Exception.Message)
                }
            }
            else {
                # if the uac property does not exist add all the uac properties to maintain like output
                $UACAttribs | Foreach {
                    Write-Verbose ('Append-ADUserAccountControl: useraccountcontrol property NOT found.')
                    Add-Member -InputObject $usr -MemberType NoteProperty -Name $_ -Value $null -Force
                }
                Write-Output $usr
            }
        }
    }
}

function Get-LyncEnabledObjectsFromAD {
    [cmdletbinding()]
    param(
        [Parameter(HelpMessage='Base of AD to search.')]
        $SearchBase = ''
    )

    try {
        $conn = Connect-ActiveDirectory -ADContextType:DirectoryEntry
        $DomainDN = $conn.distinguishedName
        $ConfigurationDN = 'CN=Configuration,' + $DomainDN
        if ($SearchBase -eq '') {
            $SearchBase = [string]$DomainDN
        }
    }
    catch {
        Write-Warning 'Unabled to connect to AD!'
        $conn = $null
    }
    if ($conn -ne $null) {
        $LyncContacts = @()
        $LyncUsers = @()
        $Properties = @('Name','SamAccountName','SID','distinguishedName','useraccountcontrol','msRTCSIP-UserEnabled','msExchUMEnabledFlags','msRTCSIP-Line','msrtcsip-ownerurn','msRTCSIP-PrivateLine','msrtcsip-primaryuseraddress','telephoneNumber','OfficePhone','mail','department','physicalDeliveryOfficeName')

        #$Users = @(Search-AD -DirectoryEntry $conn -Filter '(objectCategory=person)(objectClass=user)(!(useraccountcontrol:1.2.840.113556.1.4.803:=2))(msRTCSIP-Line=*)' -Properties $Properties -SearchRoot ('LDAP://' + $SearchBase))
        $LyncUsers = @(Search-AD -DirectoryEntry $conn -Filter '(objectCategory=person)(objectClass=user)(|(msRTCSIP-Line=*)(msRTCSIP-PrivateLine=*))' -Properties $Properties -SearchRoot ('LDAP://' + $SearchBase))
        $LyncUsers = $LyncUsers | Format-LyncADAccount -PhoneType 'LyncUser'

        # Get configuration partition Lync enabled items (conference and RGS numbers)
        $LyncContacts = @(Search-AD -DirectoryEntry $conn -Filter '(ObjectClass=contact)(msRTCSIP-Line=*)' -Properties $Properties -SearchRoot ('LDAP://' + $SearchBase) | Format-LyncADAccount)

        # Get UM auto-attendant numbers assigned in exchange (from AD)
        $AANumbers = @(Search-AD -DontJoinAttributeValues -DirectoryEntry $conn -Filter '(ObjectClass=msExchUMAutoAttendant)' -Properties * -SearchRoot ('LDAP://' + $ConfigurationDN) | 
        Where {$_.msExchUMAutoAttendantDialedNumbers} | Select -ExpandProperty msExchUMAutoAttendantDialedNumbers)
        $AAMatchNumbers = @($AANumbers | Foreach {[regex]::Escape($_)})
        $AAMatchNumbers = '^(' + ($AAMatchNumbers -join '|') + ')$'

        # Get all UM voicemail numbers assigned in exchange (from AD)
        $VMNumbers = @(Search-AD -DontJoinAttributeValues -DirectoryEntry $conn -Filter '(ObjectClass=msExchUMDialPlan)' -Properties * -SearchRoot ('LDAP://' + $ConfigurationDN) | 
        Where {($_.msExchUMVoiceMailPilotNumbers).Count -gt 0} | Select -ExpandProperty msExchUMVoiceMailPilotNumbers)
        $VMMatchNumbers = @($VMNumbers | Foreach {[regex]::Escape($_)})
        $VMMatchNumbers = '^(' + ($VMMatchNumbers -join '|') + ')$'

        # Look for voicemail and AA enabled contacts by matching them up with what you found in ad
        $LyncContacts | Foreach {
            $tmpURI = $_.DID -replace 'tel:',''
            if ($tmpURI -match $AAMatchNumbers) {
                $_.PhoneType = 'UM Auto Attendant'
            }
            elseif ($tmpURI -match $VMMatchNumbers) {
                $_.PhoneType = 'UM Voicemail'
            }
        }
        
        Write-Output $LyncUsers
        Write-Output $LyncContacts
    }
}

### Project Specific Functions
function New-RegexFromRange {
    # Courtesy (mostly) of http://rxnrg.codeplex.com/
    [CmdletBinding()] 
    param (
        [Parameter(Position=0, Mandatory=$true, HelpMessage='Start of number range.')]
        [string]$startrange,
        [Parameter(Position=1, Mandatory=$true, HelpMessage='End of number range.')] 
        [string]$endrange
    )
    begin {
        $rxnrgCode = @'
            using System;
            using System.Collections.Generic;
            using System.Globalization;
            using System.Text;
            public class RegexNumRangeGen
            {
            	public static string Generate(string a, string b)
            	{
            		if (a == null)
            		{
            			throw new ArgumentNullException("a");
            		}

            		if (b == null)
            		{
            			throw new ArgumentNullException("b");
            		}

            		if (a.Length == 0 || TextHelper.IsDigit(a) != -1)
            		{
            			throw new ArgumentException("A is not a number.", "a");
            		}

            		if (b.Length == 0 || TextHelper.IsDigit(b) != -1)
            		{
            			throw new ArgumentException("B is not a number.", "b");
            		}

            		a = a.Remove(0, TextHelper.FindRep('0', a, 0, a.Length - 2));
            		b = b.Remove(0, TextHelper.FindRep('0', b, 0, b.Length - 2));

            		if (TextHelper.Compare(a, b) > -1)
            		{
            			string c = a;
            			a = b;
            			b = c;
            		}

            		return BuildRegex(Divide(new Range() { A = a, B = b }));
            	}

            	private static List<Range> Divide(Range fullRange)
            	{
            		int diff = TextHelper.Compare(fullRange.B, fullRange.A);
            		List<Range> ranges = new List<Range>();

            		if (diff == -1)
            		{
            			ranges.Add(fullRange);
            		}
            		else
            		{
            			List<Range> bigRanges = new List<Range>();

            			for (int i = fullRange.A.Length; i <= fullRange.B.Length; i++)
            			{
            				bigRanges.Add(new Range() { A = ((i == fullRange.A.Length) ? fullRange.A : "1" + new string('0', i - 1)), B = ((i == fullRange.B.Length) ? fullRange.B : new string('9', i)), IsBig = true });
            			}

            			Range range = bigRanges[0];

            			{
            				int len = range.A.Length - 1;

            				int x = 1 + TextHelper.FindRepRight('0', range.A, len, (diff == 0) ? 1 : diff);
            				int y = range.A.Length;

            				if (diff > 0)
            				{
            					y -= diff;
            				}

            				string a = range.A;

            				for (int i = x; i <= y; i++)
            				{
            					int b = i - 1;

            					if (i > x)
            					{
            						a = String.Concat(new string[] { a.Substring(0, a.Length - b - 1), ((char)(a[len - b] + 1)).ToString(), new string('0', b) });
            					}

            					i += TextHelper.FindRepRight('9', range.A, len - i, 0);

            					if (i > y)
            					{
            						i -= 1;
            					}

            					ranges.Add(new Range() { A = a, B = range.A.Substring(0, range.A.Length - i) + new string('9', i) });
            				}
            			}

            			{
            				int len = bigRanges.Count - 1;

            				for (int i = 1; i < len; i++)
            				{
            					ranges.Add(bigRanges[i]);
            				}
            			}

            			range = (diff == 0) ?
            				bigRanges[bigRanges.Count - 1] :
            				(ranges.Count == 0) ?
            				fullRange : new Range() { A = String.Concat(new string[] { fullRange.A.Substring(0, diff - 1), ((char)(fullRange.A[diff - 1] + 1)).ToString(), new string('0', fullRange.A.Length - diff) }), B = fullRange.B };

            			if (range.A == range.B)
            			{
            				ranges.Add(range);
            			}
            			else
            			{
            				int x = TextHelper.Compare(range.B, range.A);
            				int y = range.B.Length - TextHelper.FindRepRight('9', range.B, range.B.Length - 1, x);
            				string a = range.A;

            				for (int i = x; i <= y; i++)
            				{
            					if (i > x)
            					{
            						a = range.B.Substring(0, i - 1) + new string('0', range.B.Length - i + 1);
            					}

            					i += TextHelper.FindRep('0', range.B, i - 1, y - 1);

            					if (i > y)
            					{
            						i -= 1;
            					}

            					ranges.Add(new Range() { A = a, B = ((i == y) ? range.B : String.Concat(new string[] { range.B.Substring(0, i - 1), ((char)(range.B[i - 1] - 1)).ToString(), new string('9', range.B.Length - i) })) });
            				}
            			}
            		}

            		return ranges;
            	}

            	private static string BuildRegex(List<Range> ranges)
            	{
            		StringBuilder sb = new StringBuilder();

            		if (ranges.Count > 1)
            		{
            			sb.Append('(');
            		}

            		int rangesLen = ranges.Count - 1;

            		for (int rangesIndex = 0; rangesIndex <= rangesLen; rangesIndex++)
            		{
            			if (rangesIndex != 0)
            			{
            				sb.Append('|');
            			}

            			Range range = ranges[rangesIndex];

            			int length = range.A.Length;

            			for (int index = 0; index < length; index++)
            			{
            				char c1 = range.A[index];
            				char c2 = range.B[index];

            				if (c1 == c2)
            				{
            					sb.Append(c1);
            				}
            				else
            				{
            					sb.Append('[');
            					sb.Append(c1);

            					if (c2 - c1 != 1)
            					{
            						sb.Append('-');
            					}

            					sb.Append(c2);
            					sb.Append(']');

            					if (c1 == '0' && c2 == '9')
            					{
            						int oldRangesIndex = rangesIndex;

            						while (true)
            						{
            							if (rangesIndex == rangesLen)
            							{
            								Range newRange = ranges[rangesIndex];

            								if (rangesIndex != oldRangesIndex && TextHelper.FindRep('9', newRange.B, 0, newRange.B.Length - 1) != newRange.B.Length)
            								{
            									rangesIndex--;
            								}

            								break;
            							}
            							else if (!ranges[rangesIndex].IsBig)
            							{
            								if (rangesIndex != oldRangesIndex)
            								{
            									rangesIndex--;
            								}

            								break;
            							}

            							rangesIndex++;
            						}

            						int q1 = length - index;
            						int q2 = q1 + (rangesIndex - oldRangesIndex);

            						if (q1 > 1 || q2 > 1)
            						{
            							sb.Append('{');
            							sb.Append(q1.ToString(CultureInfo.InvariantCulture));

            							if (q2 > q1)
            							{
            								sb.Append(',');
            								sb.Append(q2.ToString(CultureInfo.InvariantCulture));
            							}

            							sb.Append('}');
            						}

            						break;
            					}
            				}
            			}
            		}

            		if (ranges.Count > 1)
            		{
            			sb.Append(')');
            		}

            		return sb.ToString();
            	}

            	private struct Range
            	{
            		public string A;
            		public string B;
            		public bool IsBig;
            	}

            	private static class TextHelper
            	{
            		private static int[] charmap = new int[]
            		{
            			1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            			1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0, 0, 0,
            			0, 0, 0, 0, 0, 0, 0, 0, 36, 36, 36, 36, 36, 36, 36, 36, 36, 36, 0, 0,
            			0, 0, 0, 0, 0, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40,
            			40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 0, 0, 0, 0, 32, 0, 48, 48, 48,
            			48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48,
            			48, 48, 48, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
            			1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
            		};
            		private static int charmapLength = 160;

            		public static bool IsDigit(char c)
            		{
            			return ((c < charmapLength) && ((charmap[c] & 4) != 0));
            		}

            		public static int IsDigit(string s)
            		{
            			return Validate(s, IsDigit);
            		}

            		public static int Validate(string str, Func<char, bool> validator)
            		{
            			int length = str.Length;

            			for (int index = 0; index < length; index++)
            			{
            				if (!validator.Invoke(str[index]))
            				{
            					return index;
            				}
            			}

            			return -1;
            		}

            		public static int Compare(string str1, string str2)
            		{
            			if (str1.Length > str2.Length)
            			{
            				return 0;
            			}

            			if (str1.Length == str2.Length)
            			{
            				int length = str1.Length;

            				for (int index = 0; index < length; index++)
            				{
            					if (str1[index] > str2[index])
            					{
            						return index + 1;
            					}

            					if (str1[index] < str2[index])
            					{
            						return -3;
            					}
            				}

            				return -1;
            			}

            			return -2;
            		}

            		public static int FindRep(char chr, string str, int beginPos, int endPos)
            		{
            			int pos;

            			for (pos = beginPos; pos <= endPos; pos++)
            			{
            				if (str[pos] != chr)
            				{
            					break;
            				}
            			}

            			return pos - beginPos;
            		}

            		public static int FindRepRight(char chr, string str, int beginPos, int endPos)
            		{
            			int pos;

            			for (pos = beginPos; pos >= endPos; pos--)
            			{
            				if (str[pos] != chr)
            				{
            					break;
            				}
            			}

            			return beginPos - pos;
            		}
            	}
            }
        
'@
        try {
            Add-Type -ErrorAction Stop -Language:CSharpVersion3 -TypeDefinition $rxnrgCode
        }
        catch {
            Write-Error $_.Exception.Message
            break
        }
    }
    process {}
    end {
        [RegexNumRangeGen]::Generate($startrange,$endrange)
    }
}

function Get-NumberRangeOverlap {
    [CmdletBinding()] 
    param (
        [Parameter(Position=0, Mandatory=$true, HelpMessage='Start of number range.')]
        [int]$startrange1,
        [Parameter(Position=1, Mandatory=$true, HelpMessage='End of number range.')]
        [int]$endrange1,
        [Parameter(Position=3, Mandatory=$true, HelpMessage='Start of number range.')]
        [int]$startrange2,
        [Parameter(Position=4, Mandatory=$true, HelpMessage='End of number range.')]
        [int]$endrange2,
        [Parameter(Position=5, HelpMessage='Return only non-overlapping numbers instead.')]
        [switch]$InverseResults,
        [Parameter(Position=6, HelpMessage='Return if the match is source from range1 or range2')]
        [switch]$TagResults
    )
    $range1flipped = $false
    $range2flipped = $false
    if ($endrange1 -lt $startrange1) {
        $tmpendrange = $startrange1
        $startrange1 = $endrange1
        $endrange1 = $tmpendrange
        $range1flipped = $true
    }
    if ($endrange2 -lt $startrange2) {
        $tmpendrange = $startrange2
        $startrange2 = $endrange2
        $endrange2 = $tmpendrange
        $range2flipped = $true
    }
    
    # if there are no overlaps and we are not inversing results then there is nothing to do
    if ( -not 
        ((($startrange1 -le $endrange2) -and ($startrange1 -ge $startrange2)) -or 
        (($endrange1 -ge $startrange1) -and ($endrange1 -le $endrange2)) -or 
        (($startrange2 -le $endrange1) -and ($startrange2 -ge $startrange1)) -or 
        (($endrange2 -ge $startrange2) -and ($endrange2 -le $endrange1)))
       ) {
        if (-not $InverseResults) {
            break
        }
    }
    function Get-Results ($x, $tagged, $range) {
        if (-not $tagged) { $x }
        else { New-Object psobject -Property @{'range' = $range; 'number' = $x} }
    }
    $Results = @()
    # Check first range against second range
    for ($index = $startrange1; $index -le $endrange1; $index++) {
        $foundmatch = $false
        if (($index -ge $startrange2) -and ($index -le $endrange2)) {
            $foundmatch = $true
        }
        if ($foundmatch -and (-not $InverseResults)) { $Results += Get-Results $index $TagResults 'range1' }
        elseif ((-not $foundmatch) -and $InverseResults) { $Results += Get-Results $index $TagResults 'range1' }
    }
    if ($InverseResults) {
        for ($index = $startrange2; $index -le $endrange2; $index++) {
            $foundmatch = $false
            if (($index -ge $startrange1) -and ($index -le $endrange1)) {
                $foundmatch = $true
            }
            #if ($foundmatch -and (-not $InverseResults)) { $Results += Get-Results $index $TagResults 'range2' }
            if (-not $foundmatch) { 
                $Results += Get-Results $index $TagResults 'range2' }
        }
    }
    if ($TagResults) {
        $Results
    }
    else {
        $Results | Select -Unique
    }
}

function Convert-ToNumberRange {
    [CmdletBinding()] 
    param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, HelpMessage='Range of numbers in array.')]
        [int[]]$series
    )
    begin {
        $numberseries = @()
    }
    process {
        $numberseries += $series
    }
    end {
        $numberranges = @()
        $numberseries = @($numberseries | Sort | Select -Unique)
        $index = 1
        $initmode = $true
        $start = $numberseries[0]
        if ($numberseries.Count -eq 1) {
            return New-Object psobject -Property @{
                'Begin' = $numberseries[0]
                'End' = $numberseries[0]
            }
        }
        do {
            if (-not $initmode) {
                if (($numberseries[$index] - $numberseries[$index - 1]) -ne 1) {
                    New-Object psobject -Property @{
                        'Begin' = $start
                        'End' = $numberseries[$index-1]
                    }
                    $start = $numberseries[$index]
                    $initmode = $true
                }
            }
            else {
                $initmode = $false
            }
            $index++
        } until ($index -eq ($numberseries.length))
        New-Object psobject -Property @{
            'Begin' = $start
            'End' = $numberseries[$index - 1]
        }
    }
}

function Get-SiteDialPlanOverlaps {
    [CmdletBinding()] 
    param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, HelpMessage='Object containing number ranges.')]
        [psobject[]]$Obj,
        [Parameter(Position=1, HelpMessage='Number of trailing digits to use to compare number overlap ranges.')] 
        [uint64]$Digits=0
    )
    begin {
        $Ranges = @()
        $NewRanges = @()
        $TempRanges = @()
        $Count = 0
    }
    process {
        $Ranges += $Obj
    }
    end {
        $Ranges = $Ranges | Sort-Object -Property DIDStart

        Foreach ($DIDRange in $Ranges) {
            $tmpObj = $DIDRange.PsObject.Copy()
            $tmpObj | Add-Member -MemberType NoteProperty -Name Overlapped -Value $false
            $tmpObj | Add-Member -MemberType NoteProperty -Name Index -Value $Count
            $tmpObj | Add-Member -MemberType ScriptMethod -Name UpdateRanges -Value { 
                param ( 
                    [string]$start,
                    [string]$end
                ) 
                $this.DigitsStart = $start
                $this.DigitsEnd = $end
            }
            $tmpObj | Add-Member -MemberType ScriptMethod -Name ContainsRange -Value { 
                param ( 
                    [string]$start,
                    [string]$end
                ) 
                if (($this.DigitsStart -eq $start) -and ($this.DigitsEnd -eq $end) -or 
                    ($this.DigitsEnd -eq $start) -and ($this.DigitsStart -eq $end)) {
                    $true
                }
                else {
                    $false
                }
            }
            $NewRanges += $tmpObj
            $Count++
        }
        
        $NewRanges = $NewRanges | Sort-Object -Property DigitsStart
        if ($NewRanges.Count -gt 1) {
            do {
                $overlapsfound = $false
                for ($i = 0; $i -lt $NewRanges.Count; $i++) {
                	for ($i2 = $i; $i2 -lt $NewRanges.Count; $i2++) {
                	    if (($i -ne $i2) -and (-not $NewRanges[$i].Overlapped) -and (-not $NewRanges[$i2].Overlapped)) {
                            $overlap = @(Get-NumberRangeOverlap -startrange1 ('11' + $NewRanges[$i].'DigitsStart') `
                                                                -endrange1 ('11' + $NewRanges[$i].'DigitsEnd') `
                                                                -startrange2 ('11' + $NewRanges[$i2].'DigitsStart') `
                                                                -endrange2 ('11' + $NewRanges[$i2].'DigitsEnd'))
                            Write-Verbose "Test Ranges($i - $i2): $($NewRanges[$i].'DigitsStart')-$($NewRanges[$i].'DigitsEnd') and $($NewRanges[$i2].'DigitsStart')-$($NewRanges[$i2].'DigitsEnd')"
                            if ($overlap.count -ge 1) {
                                $overlaprange = $overlap | Convert-ToNumberRange
                                $_start = if ($overlaprange.Begin -match '^11(.*)$') {[string]$Matches[1]} else {[string]$overlaprange.Begin}
                                $_end = if ($overlaprange.End -match '^11(.*)$') {[string]$Matches[1]} else {[string]$overlaprange.End}
                                # If an overlap has been found then create new ranges consisting of:
                                # - The overlap range for the first set
                                $Count++
                                $tmpObj = $NewRanges[$i2].PsObject.Copy()
                                $tmpObj.Overlapped = $true
                                $tmpObj.Index = $Count
                                $tmpObj.UpdateRanges($_start,$_end)
                                $TempRanges += $tmpObj
                                $overlapsfound = $true

                                $tmpObj = $NewRanges[$i].PsObject.Copy()
                                $tmpObj.Overlapped = $true
                                $tmpObj.Index = $Count
                                $tmpObj.UpdateRanges($_start,$_end)
                                $TempRanges += $tmpObj
                                $overlapsfound = $true

                                $nonoverlap = @(Get-NumberRangeOverlap -startrange1 ('11' + $NewRanges[$i].'DigitsStart') `
                                                              -endrange1 ('11' + $NewRanges[$i].'DigitsEnd') `
                                                              -startrange2 ('11' + $NewRanges[$i2].'DigitsStart') `
                                                              -endrange2 ('11' + $NewRanges[$i2].'DigitsEnd') `
                                                              -InverseResults -TagResults)

                                # - The first range up to the overlap range
                                if (($nonoverlap | Where {$_.range -eq 'range1'}).Count -gt 0) {
                                    $nonoverlaprange = ($nonoverlap | Where {$_.range -eq 'range1'}).Number | Convert-ToNumberRange
                                    $_start = if ($nonoverlaprange.Begin -match '^11(.*)$') {[string]$Matches[1]} else {[string]$nonoverlaprange.Begin}
                                    $_end = if ($nonoverlaprange.End -match '^11(.*)$') {[string]$Matches[1]} else {[string]$nonoverlaprange.End}
                                    if (($TempRanges).Index -contains ($NewRanges[$i]).Index) {
                                        $TempRanges | Where {$_.Index -eq ($NewRanges[$i]).Index} | Foreach {
                                            $_.UpdateRanges($_start,$_end)
                                        }
                                    }
                                    else {
                                        $tmpObj = $NewRanges[$i].PsObject.Copy()
                                        $tmpObj.UpdateRanges($_start,$_end)
                                        $TempRanges += $tmpObj
                                    }
                                }

                                # - The second range up to the overlap range
                                if (($nonoverlap | Where {$_.range -eq 'range2'}).Count -gt 0) {
                                    $nonoverlaprange = ($nonoverlap | Where {$_.range -eq 'range2'}).Number | Convert-ToNumberRange
                                    $_start = if ($nonoverlaprange.Begin -match '^11(.*)$') {[string]$Matches[1]} else {[string]$nonoverlaprange.Begin}
                                    $_end = if ($nonoverlaprange.End -match '^11(.*)$') {[string]$Matches[1]} else {[string]$nonoverlaprange.End}
                                    if (($TempRanges).Index -contains ($NewRanges[$i2]).Index) {
                                        $TempRanges | Where {$_.Index -eq ($NewRanges[$i2]).Index} | Foreach {
                                            $_.UpdateRanges($_start,$_end)
                                        }
                                    }
                                    else {
                                        $tmpObj = $NewRanges[$i2].PsObject.Copy()
                                        $tmpObj.UpdateRanges($_start,$_end)
                                        $TempRanges += $tmpObj
                                    }
                                }
                            }
                            else {
                                if (-not (($TempRanges).Index -contains $NewRanges[$i].Index)) {
                                    $tmpObj = $NewRanges[$i] | Select *
                                    $TempRanges += $tmpObj
                                }
                                if ((-not (($TempRanges).Index -contains $NewRanges[$i2].Index)) -and 
                                    (-not $overlapsfound) -and 
                                    (($NewRanges.Count - 1) -eq $i2)
                                   ) {
                                    $tmpObj = $NewRanges[$i2].PsObject.Copy()
                                    $TempRanges += $tmpObj
                                }
                            }
                        }
                    }
                }
                $NewRanges = @()
                $TempRanges | Foreach {$NewRanges += $_.PsObject.Copy()}
            } While ($overlapsfound)
        }
        else {
            $tmpObj = $NewRanges.PsObject.Copy()
            $tmpObj | Add-Member -MemberType NoteProperty -Name Overlapped -Value $false
            $tmpObj | Add-Member -MemberType NoteProperty -Name Index -Value 1
            $NewRanges = $tmpObj
        }
        return $NewRanges
    }
}

#function New-SiteDialPlanTransform {
#    [CmdletBinding()] 
#    param (
#        [Parameter(Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Site code for intrasite calling.')]
#        [string]$SiteDialCode = '',
#        [Parameter(Position=1, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Site name.')]
#        [string]$SiteName,
#        [Parameter(Position=2, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Beginning of DID range.')] 
#        [string]$DIDStart,
#        [Parameter(Position=3, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='End of DID range.')] 
#        [string]$DIDEnd,
#        [Parameter(Position=4, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Number of trailing digits to use for local dialling.')] 
#        [uint64]$Digits=0,
#        [Parameter(Position=5, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Number of trailing digits to use for local dialling.')] 
#        [bool]$LocalRange,
#        [Parameter(Position=6, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Number of trailing digits to use for local dialling.')] 
#        [bool]$PrivateRange,
#        [Parameter(Position=7, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='End of DID range.')] 
#        [string]$MainNumber = ''
#    )
#    begin {
#        $Entries = @()
#        $Output = @()
#        $RegexResults = @()
#        $PriorPrivRange = $null
#        $PriorPrefix = $null
#        $Count = 0
#    }
#    process {
#        $Entries += New-Object psobject -Property $PSBoundParameters
#    }
#    end {
#        # First sort the entries so we can do a logical grouping later on (for combining results)
#        $Entries = $Entries | Sort-Object -Property PrivateRange,MainNumber,DIDStart
#        
#        Foreach ($DIDRange in $Entries) {            
#            # Store the ranges based on the digit counts, add 11 at the beginning as a method for retaining preceeding zeros
#            $ExtStart = '11' + ($DIDRange.DIDStart).substring(($DIDRange.DIDStart).length - $DIDRange.Digits, $DIDRange.Digits)
#            $ExtEnd = '11' + ($DIDRange.DIDEnd).substring(($DIDRange.DIDEnd).length - $DIDRange.Digits, $DIDRange.Digits)
#            
#            if ($DIDRange.PrivateRange) {
#                $Prefix = $MainNumber
#            }
#            else {
#                # Based on your did digit cound pull the prefix from your range (ie: 1222333-<4 digits>)
#                $Prefix = (($DIDRange.DIDStart).substring(0,($DIDRange.DIDStart).length - $DIDRange.Digits))
#            }
#            
#            # If we are in a new break in the transform grouping then take action, reset some counters, and spit out some results
#            if (($RegexResults.Count -gt 0) -and (($PriorPrivRange -ne $DIDRange.PrivateRange) -or ($PriorPrefix -ne $Prefix))) {
#                
#                $RegexResults = @()
#            }
#
#            # Create our regex from the ranges and strip out the dummy 'll' at the begining of the results
#            $tmpRegex = New-RegexFromRange -startrange $ExtStart -endrange $ExtEnd
#            if ($tmpRegex -match '^11(.*)$') {
#                $tmpRegex = $Matches[1]
#            }
#            else {
#                $tmpRegex = $tmpRegex -replace '\|11','|' -replace '\(11','' -replace '\)','' -replace '\(',''
#            }
#            $RegexResults += $tmpRegex
#
#            # Determine if the digit range is part of a group of ranges by looking at the prefix.
#            #  if the prefix doesn't match the prior prefix then this is a new group of expressions
#
#            if ($Prefix -ne '') {
#                if (($DIDRange.SiteDialCode -eq '') -or ($DIDRange.SiteDialCode -eq $null)) {
#                    $IntraSiteRegex = $null
#                }
#                else {
#                    $IntraSiteRegex = '^' + $DIDRange.SiteDialCode +'(' + ($RegexResults -join '|') + ')$'
#                }
#                if ($chkFullExtensionTransforms.IsChecked -or $PrivateRange) {
#                    $transform = '+' + $Prefix + '$1' + ';ext=$1'
#                }
#                else {
#                    $transform = '+' + $Prefix + '$1'
#                }
#                $Output += New-Object psobject -Property @{
#                    'EntryName' = $DIDRange.SiteName +'-' + $Count
#                    'LocalExt' = '^(' + ($RegexResults -join '|') + ')$'
#                    'InterSiteExt' = $IntraSiteRegex
#                    'Transform' = $transform
#                    'LocalRange' = $PriorLocality #$DIDRange.LocalRange
#                }
#                $Count++
#                $RegexResults = @()
#                $Prefix = ($DIDRange.DIDStart).substring(0,($DIDRange.DIDStart).length - $DIDRange.Digits)
#            }
#            else {
#                $Prefix = ($DIDRange.DIDStart).substring(0,($DIDRange.DIDStart).length - $DIDRange.Digits)
#                $PriorLocality = $DIDRange.LocalRange
#            }
#            
#            $PriorPrefix = $Prefix
#            $PriorPrivRange = $DIDRange.PrivateRange
#        }
#        
#        if (($DIDRange.SiteDialCode -eq '') -or ($DIDRange.SiteDialCode -eq $null)) {
#            $InterSiteRegex = $null
#        }
#        else {
#            $InterSiteRegex = '^' + $DIDRange.SiteDialCode +'(' + ($RegexResults -join '|') + ')$'
#        }
#        if (($chkFullExtensionTransforms.IsChecked -or $PrivateRange) -and ($Prefix -ne '')) {
#            $transform = '+' + $Prefix + '$1' + ';ext=$1'
#        }
#        else {
#            $transform = '+' + $Prefix + '$1'
#        }
#        $Output += New-Object psobject -Property @{
#            'EntryName' = $DIDRange.SiteName +'-' + $Count
#            'LocalExt' = '^(' + ($RegexResults -join '|') + ')$'
#            'InterSiteExt' = $InterSiteRegex
#            'Transform' = $transform
#            'LocalRange' = $DIDRange.LocalRange
#        }
#
#        $Output
#    }
#}

function New-SiteDialPlanTransform {
    [CmdletBinding()] 
    param (
        [Parameter(Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, HelpMessage='Site code for intrasite calling.')]
        [psobject]$DIDRangeEntry,
        [Parameter(Position=1, HelpMessage='Number of trailing digits to use for local dialing.')] 
        [uint64]$Digits = 0,
        [Parameter(Position=2, HelpMessage='Simplified transforms')]
        [bool]$SimplifiedTransforms = $false
    )
    begin {
        $Entries = @()
        $Output = @()
        $RegexResults = @()
        $PriorPrivRange = $null
        $PriorPrefix = $null
        $Count = 0
    }
    process {
        $Entries += $DIDRangeEntry
    }
    end {
        # First sort the entries so we can do a logical grouping later on (for combining results)

        $Entries | Foreach {
            Add-Member -force -InputObject $_ -MemberType NoteProperty -Name 'RangeType' -Value (Get-DIDRangeType $_.LocalRange $_.PrivateRange)
            if (($_.RangeType -eq 'localpriv') -or ($_.RangeType -eq 'nonlocalpriv')) {
                $_.DIDPrefix = $_.MainNumber
            }
        }
        $Entries = $Entries | Sort-Object -Property RangeType,DIDPrefix

        # Get some shared values for later
        $SiteName = ($Entries | Select -First 1).SiteName
        $SiteCode = ($Entries | Select -First 1).SiteDialCode

        # go through each of the range types
        $RangeTypes = @(($Entries).RangeType)

        Foreach ($RangeType in $RangeTypes) {
            $SubEntries = $Entries | Where {$_.RangeType -eq $RangeType}
            # and through each of the prefixes (sigh)
            $Prefixes = ($SubEntries).DIDPrefix
            Foreach ($UniquePrefix in $Prefixes) {
                $RegexResults = @()
                Foreach ($DIDRange in ($SubEntries | Where {$_.DIDPrefix -eq $UniquePrefix})) {
                    # Store the ranges based on the digit counts, add 11 at the beginning as a method for retaining preceeding zeros
                    $ExtStart = [string]'11' + ($DIDRange.DIDStart).substring(($DIDRange.DIDStart).length - $Digits, $Digits)
                    $ExtEnd = [string]'11' + ($DIDRange.DIDEnd).substring(($DIDRange.DIDEnd).length - $Digits, $Digits)

                    # Create our regex from the ranges and strip out the dummy 'll' at the begining of the results
                    $tmpRegex = New-RegexFromRange -startrange $ExtStart -endrange $ExtEnd
                    if ($tmpRegex -match '^11(.*)$') {
                        $tmpRegex = $Matches[1]
                    }
                    else {
                        $tmpRegex = $tmpRegex -replace '\|11','|' -replace '\(11','' -replace '\)','' -replace '\(',''
                    }
                    $RegexResults += $tmpRegex
                }

                $LocalExt = '^(' + ($RegexResults -join '|') + ')$'
                $Count++                
                $EntryName =  $SiteName +'-' + $Count
                $InterSiteRegex = $null

                switch ($RangeType) {
                    'localpriv' {
                        $LocalRange = $true
                        $PrivateRange = $true
                        $transform = '+' + $UniquePrefix + ';ext=$1'
                    }
                    'nonlocalpriv' {
                        $LocalRange = $false
                        $PrivateRange = $true
                        $transform = '+' + $UniquePrefix + ';ext=' + $DialCode + '$1'
                        if (($SiteCode -ne '') -and ($SiteCode -ne $null)) {
                            $InterSiteRegex = '^' + $SiteCode +'(' + ($RegexResults -join '|') + ')$'
                        }
                    }
                    'nonlocalpub' {
                        $LocalRange = $false
                        $PrivateRange = $false
                        if ($chkFullExtensionTransforms.IsChecked) {
                            $transform = '+' + $UniquePrefix + '$1' + ';ext=' + $DialCode + '$1'
                        }
                        else {
                            $transform = '+' + $UniquePrefix + '$1'
                        }
                        if (($SiteCode -ne '') -and ($SiteCode -ne $null)) {
                            $InterSiteRegex = '^' + $SiteCode +'(' + ($RegexResults -join '|') + ')$'
                        }
                    }
                    'localpub' {
                        $LocalRange = $true
                        $PrivateRange = $false
                        if ($chkFullExtensionTransforms.IsChecked) {
                            $transform = '+' + $UniquePrefix + '$1' + ';ext=' + '$1'
                        }
                        else {
                            $transform = '+' + $UniquePrefix + '$1'
                        }
                    }
                }

                # If we had no DID prefix then take corrective action...
                $transform = $transform.Replace('+$1;ext=','+')

                New-Object psobject -Property @{
                    'EntryName' = $EntryName
                    'LocalExt' = $LocalExt
                    'InterSiteExt' = $InterSiteRegex
                    'Transform' = $transform
                    'LocalRange' = $LocalRange
                    'PrivateRange' = $PrivateRange
                }
            }
        }
    }
}

function Validate-LocalDigitLength {
    $minRangeLen = $null
    foreach ($item in $listviewDIDs.Items) {
        $tmpDIDLen = if (($item.DIDStart).Length -lt ($item.DIDEnd).Length) {($item.DIDStart).Length} else {($item.DIDEnd).Length}
        $minRangeLen = if ($minRangeLen -eq $null) {$tmpDIDLen} else {if ($tmpDIDLen -lt $minRangeLen) {$tmpDIDLen}}
    }
    
    if (($minRangeLen -lt $txtOptionLocalDigits.text) -and (-not ($minRangeLen -eq $null))) {
        $txtOptionLocalDigits.BorderThickness=2
        $txtOptionLocalDigits.BorderBrush='#FFF21A11'
        $txtblockDescription.Text = 'DID ranges are less digits than the site local digit count!'
        return $false
    }
    else {
        $txtOptionLocalDigits.BorderThickness=1
        $txtOptionLocalDigits.BorderBrush='#FFABADB3'
        return $true
    }
}

function Recalculate-DIDRanges {
    $Count = 0
    foreach ($item in $listviewDIDs.Items) {
        $Digits = $txtOptionLocalDigits.text
        $DIDStart = $item.DIDStart
        $DIDEnd = $item.DIDEnd
        if ((($DIDStart - $Digits) -lt 0) -or (($DIDEnd - $Digits) -lt 0)) {
            $txtOptionLocalDigits.BorderThickness=2
            $txtOptionLocalDigits.BorderBrush='#FFF21A11'
            $txtblockDescription.Text = 'This digit length is larger than your DID ranges!'
        }
        else {
            $DigitsStart = ($DIDStart).substring(($DIDStart).length - $Digits, $Digits)
            $DigitsEnd = ($DIDEnd).substring(($DIDEnd).length - $Digits, $Digits)
            $PrefixStart = ($DIDStart).substring(0,($DIDStart).length - $Digits)
            $PrefixEnd = ($DIDEnd).substring(0,($DIDEnd).length - $Digits)
            if ($PrefixStart -eq $PrefixEnd) {
                if (-not $item.PrivateRange -eq 'False') {
                    $listviewDIDs.Items[$Count].DIDPrefix = $PrefixStart
                }
                $listviewDIDs.Items[$Count].DigitsStart = $DigitsStart
                $listviewDIDs.Items[$Count].DigitsEnd = $DigitsEnd
                $listviewDIDs.Items.Refresh()
                $txtOptionLocalDigits.BorderThickness=1
                $txtOptionLocalDigits.BorderBrush='#FFABADB3'
            }
            else {
                $txtOptionLocalDigits.BorderThickness=2
                $txtOptionLocalDigits.BorderBrush='#FFF21A11'
                $txtblockDescription.Text = 'This digit length would result in multiple (thus ambiguous) DID prefixes! To use this digit length please split this DID range so that all unique prefixes are in their own range.'
            }
        }
        $Count++
    }
}
function Get-DIDRangeType {
    [CmdletBinding()] 
    param (
        [Parameter(Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [bool]$LocalRange = $false,
        [Parameter(Position=1, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)] 
        [bool]$PrivateRange = $false
    )
    if ($LocalRange -and $PrivateRange) {return 'localpriv'}
    if ((-not $LocalRange) -and $PrivateRange) {return 'nonlocalpriv'}
    if ((-not $LocalRange) -and (-not $PrivateRange)) {return 'nonlocalpub'}
    if ($LocalRange -and (-not $PrivateRange)) {return 'localpub'}
}

function Generate-DIDRangeExport {
    <# Function Used to create the export ranges and such
     Example Input:
        Site Code       - 20
        DID Range Start - 1-555-555-1000
        DID Range End   - 1-555-555-1100
        Main Number     - 1-555-555-1101
        DID Digit Count - 4
     Example Output:
        Non-Local/Public Number: tel:+15555551000;ext=201000
        Local/Public Number: tel:+15555551000;ext=1000
        Non-Local/Private Number: tel:+15555551101;ext=201000
        Local/Private Number: tel:+15555551101;ext=1000
    #>
    
    # Start from scratch (remove existing range data if it exists)
    $listviewDIDRangeExport.Items.Clear()

    $tempDIDs = @()
    foreach ($item in $listviewDIDs.Items) {
        # make and work with a copy of each object
        $tmpObj = $item.PsObject.Copy()
        # Add a distinguishing property to filter out duplicates
        $tmpObj | Add-Member -MemberType NoteProperty -Name FullRange -Value ($item.MainNumber + $item.DIDStart + '-' + $item.MainNumber + $item.DIDEnd)
        $tmpObj.LocalRange = ($tmpObj.LocalRange -eq 'TRUE')    # cute little hack to turn a string into a bool
        $tmpObj.PrivateRange = ($tmpObj.PrivateRange -eq 'TRUE')
        $tempDIDs += $tmpObj
    }
    $RangesToExport = @($tempDIDs | Sort-Object -Property Site,DIDStart | Select-Unique -Property FullRange)
    $RangesToExport | Foreach {
        $RangeProp = @{
            'SiteName' = $_.SiteName
            'SiteCode' = $_.SiteDialCode
            'LineURI' = ''
            'DDI' = ''
            'Ext' = ''
            'Name' = ''
            'FirstName' = ''
            'LastName' = ''
            'SIPAddress' = ''
            'Type' = ''
            'Private' = $_.PrivateRange
            'Local' = $_.LocalRange
            'Notes' = ''
        }
        
        $SiteCode = $RangeProp.SiteCode    # Just to shorten code later
        
        # First we append some arbitrary numbers to our ranges so we can retain preceeding zeros when needed
        $rangestart = "22$($_.DigitsStart)"
        $rangeend = "22$($_.DigitsEnd)"
        $PrivRange = $_.PrivateRange
        $LocalRange = $_.LocalRange
        $ExtStr = ';ext='
        if ($PrivRange) {
            if (($_.MainNumber -ne $null) -and ($_.MainNumber -ne '')) {
                $DIDPrefix = $_.MainNumber
            }
            else {
                $DIDPrefix = ''
                $ExtStr = ''
            }
        }
        else {
            $DIDPrefix = $_.DIDPrefix
        }
        
        # and the fun begins...
        $RangeType = Get-DIDRangeType $LocalRange $PrivRange
#        if ($LocalRange -and $PrivRange) {$RangeType = 'localpriv'}
#        if ((-not $LocalRange) -and $PrivRange) {$RangeType = 'nonlocalpriv'}
#        if ((-not $LocalRange) -and (-not $PrivRange)) {$RangeType = 'nonlocalpub'}
#        if ($LocalRange -and (-not $PrivRange)) {$RangeType = 'localpub'}
        
        $rangestart..$rangeend | Foreach {
            # First remove our marker numbers to get the real current extension number
            $ActualNumber = if ($_ -match '^22(.*)$') {[string]$Matches[1]} else {[string]$_}

            switch ($RangeType) {
                'localpriv' {
                    # Local/Private Number - tel:+15555551101;ext=1000
                    $RangeProp.LineURI = 'tel:+' + $DIDPrefix + $ExtStr + $ActualNumber
                    $RangeProp.Ext = "$ActualNumber"
                    $RangeProp.DDI = if ($DIDPrefix -ne '') {"$DIDPrefix"} else {"$ActualNumber"}
                }
                'localpub' {
                    # Local/Public Number: tel:+15555551000;ext=1000
                    $RangeProp.LineURI = 'tel:+' + $DIDPrefix + $ActualNumber + $ExtStr + $ActualNumber
                    $RangeProp.Ext = "$ActualNumber"
                    $RangeProp.DDI = "$DIDPrefix$ActualNumber"
                }
                'nonlocalpriv' {
                    # Non-Local/Private Number: tel:+15555551101;ext=201000
                    $RangeProp.LineURI = 'tel:+' + $DIDPrefix + $ExtStr + $SiteCode + $ActualNumber
                    $RangeProp.Ext = "$SiteCode$ActualNumber"
                    $RangeProp.DDI = if ($DIDPrefix -ne '') {"$DIDPrefix"} else {$SiteCode + $ActualNumber}
                }
                'nonlocalpub' {
                    # Non-Local/Public Number: tel:+15555551000;ext=201000
                    $RangeProp.LineURI = 'tel:+' + $DIDPrefix + $SiteCode + $ActualNumber
                    $RangeProp.Ext = "$SiteCode$ActualNumber"
                    $RangeProp.DDI = "$DIDPrefix$ActualNumber"
                }
            }

            $RangeItem = New-Object psobject -Property $RangeProp
            $listviewDIDRangeExport.Items.Add($RangeItem)
        }
    }
}

### Form specific functions ###
function Reset-FormInputValidationState {
    $txtSiteName.BorderThickness=1
    $txtSiteDialCode.BorderThickness=1
    $txtLineNumberStart.BorderThickness=1
    $txtLineNumberEnd.BorderThickness=1
    $txtOptionLocalDigits.BorderThickness=1

    $txtSiteName.BorderBrush='#FFABADB3'
    $txtSiteDialCode.BorderBrush='#FFABADB3'
    $txtLineNumberStart.BorderBrush='#FFABADB3'
    $txtLineNumberEnd.BorderBrush='#FFABADB3'
    $txtOptionLocalDigits.BorderBrush='#FFABADB3'
    
    $txtSiteName.Tooltip = 'The name of the site associated with the DID range.'
    $txtLineNumberEnd.Tooltip = 'The end of this DID range.'
    $txtSiteDialCode.Tooltip = 'A unique dial code for this site. This gets prepended to the extension.'
    $txtOptionLocalDigits.Tooltip = 'Number of digits from end of DID which represents the extension for users.'
}

function Set-FormInputValidationState {
    $StatusOK = $true
    if ($txtSiteName.Text -eq '') {
        $StatusOK = $false
        $txtSiteName.BorderThickness=2
        $txtSiteName.BorderBrush='#FFF21A11'
        $txtSiteName.Tooltip = 'Please provide a site name!'
    }
    if ($txtLineNumberStart.Text -gt $txtLineNumberEnd.Text) {
        $StatusOK = $false
        $txtLineNumberStart.BorderThickness=2
        $txtLineNumberStart.BorderBrush.Color='#FFF21A11'
        $txtLineNumberEnd.BorderThickness=2
        $txtLineNumberEnd.BorderBrush='#FFF21A11'
        $txtLineNumberEnd.Tooltip = 'The end line number needs to come after the start line number!'
    }
    $SiteInfo = @($listviewDIDs.Items | Where {$_.SiteName -eq $txtSiteName.Text})
    if ($SiteInfo.Count -ge 1) {
        if ($txtSiteDialCode.Text -ne $SiteInfo[0].SiteDialCode) {
            $StatusOK = $false
            $txtSiteDialCode.BorderThickness=2
            $txtSiteDialCode.BorderBrush='#FFF21A11'
            $txtSiteDialCode.Tooltip = 'It makes no sense to add the same site name with different site codes!'
        }
    }
    $SiteInfo = @($listviewDIDs.Items | Where {$_.SiteDialCode -eq $txtSiteDialCode.Text})
    if ($SiteInfo.Count -ge 1) {
        if ($txtSiteName.Text -ne $SiteInfo[0].SiteName) {
            $StatusOK = $false
            $txtSiteName.BorderThickness=2
            $txtSiteName.BorderBrush='#FFF21A11'
            $txtSiteName.Tooltip = 'It makes no sense to have the same site code assigned to multiple sites!'
        }
    }
    Return $StatusOK
}

function Set-FormElementState {
    if ($chkPrivateRange.isChecked) {
        $txtMainNumber.IsEnabled = $true
    }
    else {
        $txtMainNumber.IsEnabled = $false
    }
    if ($chkADMatching.isChecked) {
        $btnSelectOU.IsEnabled = $true
        $btnRangeExportADMatch.IsEnabled = $true
    }
    else {
        $btnSelectOU.IsEnabled = $false
        $btnRangeExportADMatch.IsEnabled = $false
    }
}

function Clear-Listboxes {
    $listviewOutput.Items.Clear()
    $listviewDIDExceptions.Items.Clear()
    if (-not $chkDisableRangeExport.isChecked) {
        $listviewDIDRangeExport.Items.Clear()
    }
}
#endregion

#region global variables
# Properties to export and expected when importing input data (DID ranges)
$InputProperties = @('SiteName','SiteDialCode','DIDStart','DIDEnd','DIDPrefix','DigitsStart','DigitsEnd','LocalRange','PrivateRange','MainNumber')

$DIDs = @()
$NewNormRuleLocal = @'
New-CsVoiceNormalizationRule -Parent '<0>' -Name '<0>_<2>Digit-<1>' -Description 'Local <2> Digit local dialling for <0>' -Pattern '<3>' -Translation '<4>'
'@
$NewNormRuleInterSite = @'
New-CsVoiceNormalizationRule -Parent '<parent>' -Name '<0>_Intersite_<4>Digit-<1>' -Description 'Intersite <4> digit dialling for <0>' -Pattern '<2>' -Translation '<3>'
'@
$RemoveNormRuleKeepAll = @'
Remove-CsVoiceNormalizationRule -Identity 'Tag:<parent>/Keep All'
'@

$AddNormRuleKeepAll = @'
New-CsVoiceNormalizationRule -Parent '<parent>' -Name 'Keep All' -Pattern '^(\d+)$' -Translation '$1'
'@

$NewAnnouncementTemplate = @'
$AnnouncementServices = @{}
get-cspool | Where {$_.Services -like "ApplicationServer*"} | Foreach {
    $AnnouncementName = "UnassignedNumberAnnouncement-$(($_.fqdn -split '\.')[0])"
    $AnnouncementService = "service:ApplicationServer:$($_.fqdn)"
    $AnnouncementServices.$AnnouncementName = $AnnouncementService
    New-CsAnnouncement -Parent $AnnouncementService -Name "$AnnouncementName" -TextToSpeechPrompt '<prompt>' -Language "en-US"
}
'@

$NewCsUnassignedTemplate = @'
$AnnouncementServices.Keys | Foreach {
    $AnnouncementService = $AnnouncementServices.$_
    $AnnouncementName = $_
    $Poolname = $AnnouncementService -replace 'service:ApplicationServer:',''
    $Poolname = ($Poolname -split '\.')[0]
<unassignedranges>
}
'@
$NewCsUnassignedRange = @'
    New-CsUnassignedNumber -Identity "$($Poolname)_Unassigned_<sitename>_<count>" -NumberRangeStart '+<rangestart>' -NumberRangeEnd '+<rangeend>' -AnnouncementService $AnnouncementService -AnnouncementName $AnnouncementName
'@

[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$xamlMain = @'
<Window x:Name="windowMain"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Zach Loeber's DID Normalizer Tool" Height="720.8" Width="1012" ScrollViewer.VerticalScrollBarVisibility="Disabled" IsTabStop="False" WindowStyle="ToolWindow" ResizeMode="NoResize">
    <Window.Resources>

    </Window.Resources>
    <Grid HorizontalAlignment="Left" Width="1001">
        <GroupBox Header="Number Range Input" Margin="9,111,0,0" VerticalAlignment="Top" Height="84" HorizontalAlignment="Left" Width="638">
            <Grid Margin="0,0,-2.4,-9.4" HorizontalAlignment="Left" Width="628" Height="71" VerticalAlignment="Top">
                <Grid.RowDefinitions>
                    <RowDefinition/>
                    <RowDefinition Height="0*"/>
                </Grid.RowDefinitions>
                <TextBox x:Name="txtLineNumberStart" Margin="0,8,308,0" MaxLength="15" MaxLines="1" TextAlignment="Right" ToolTip="Start of DID range of numbers" Text="12223335555" Height="23" VerticalAlignment="Top" TabIndex="2" VerticalContentAlignment="Center" HorizontalAlignment="Right" Width="98"/>
                <TextBlock Margin="0,36,411,0" TextWrapping="Wrap" Text="DID End" VerticalAlignment="Top" Height="20" TextAlignment="Right" HorizontalAlignment="Right" Width="55"/>
                <TextBlock Margin="0,8,412,40.4" TextWrapping="Wrap" Text="DID Start" TextAlignment="Right" HorizontalAlignment="Right" Width="54"/>
                <TextBox x:Name="txtLineNumberEnd" Margin="0,37,308,0" MaxLength="15" MaxLines="1" TextAlignment="Right" ToolTip="End of DID range of numbers" Text="12223336666" Height="23" VerticalAlignment="Top" TabIndex="3" VerticalContentAlignment="Center" HorizontalAlignment="Right" Width="98"/>
                <TextBlock Margin="0,8,561,0" TextWrapping="Wrap" Text="Site Name" VerticalAlignment="Top" Height="23" TextAlignment="Right" HorizontalAlignment="Right" Width="57"/>
                <TextBox x:Name="txtSiteDialCode" HorizontalAlignment="Right" Margin="0,35,471,0" Width="85" MaxLength="4" MaxLines="1" TextAlignment="Right" ToolTip="Used in other sites to reach this site (Site Dial Code + Site Local Digits)" Height="23" VerticalAlignment="Top" TabIndex="1" VerticalContentAlignment="Center"/>
                <TextBlock Margin="0,39,564,0" TextWrapping="Wrap" VerticalAlignment="Top" Height="23" Text="Site Code" TextAlignment="Right" HorizontalAlignment="Right" Width="54"/>
                <TextBox x:Name="txtSiteName" HorizontalAlignment="Right" Text="Site1" Width="85" Margin="0,7,471,0" TextAlignment="Right" Height="23" VerticalAlignment="Top" TabIndex="0" ToolTip="Site Name. Used to arbitrarily name normalization rules." VerticalContentAlignment="Center"/>
                <CheckBox x:Name="chkLocalRange" Content="Local Range" HorizontalAlignment="Right" Margin="0,8,199,0" VerticalAlignment="Top" Height="15" Width="96" TabIndex="4"/>
                <CheckBox x:Name="chkPrivateRange" Content="Private Range" HorizontalAlignment="Right" Margin="0,7,103,0" VerticalAlignment="Top" Height="18" Width="96" TabIndex="5"/>
                <TextBlock Margin="0,41,218,12.2" TextWrapping="Wrap" Text="Main Number" HorizontalAlignment="Right" Width="77"/>
                <TextBox x:Name="txtMainNumber" Margin="0,37,103,0" MaxLength="15" MaxLines="1" TextAlignment="Right" ToolTip="Start of DID range of numbers" Text="12223335555" Height="23" VerticalAlignment="Top" TabIndex="6" VerticalContentAlignment="Center" HorizontalAlignment="Right" Width="96" IsEnabled="False"/>
                <Button x:Name="btnAdd" Content="Add" HorizontalAlignment="Left" Margin="535,-2,0,0" VerticalAlignment="Top" Width="78" TabIndex="7"/>
                <Button x:Name="btnSaveInput" Content="Save" HorizontalAlignment="Left" Margin="535,42,0,0" VerticalAlignment="Top" Width="78" UseLayoutRounding="False" TabIndex="9"/>
                <Button x:Name="btnLoad" Content="Load" HorizontalAlignment="Left" Margin="535,20,0,0" VerticalAlignment="Top" Width="78" TabIndex="8"/>
            </Grid>
        </GroupBox>
        <Button x:Name="btnGenerate" Content="Generate!" Margin="440,0,0,14" Height="20" VerticalAlignment="Bottom" HorizontalAlignment="Left" Width="108"/>
        <Button x:Name="btnRemove" Content="Remove Selected" Margin="11,329,0,0" VerticalAlignment="Top" HorizontalAlignment="Left" Width="636"/>
        <ListView x:Name="listviewDIDs" Height="124" Margin="11,200,0,0" VerticalAlignment="Top" Grid.IsSharedSizeScope="True" HorizontalAlignment="Left" Width="636">
            <ListView.ContextMenu>
                <ContextMenu Name="ContextMenuInput"  StaysOpen="true">
                    <MenuItem Header="Copy All" Name="MenuItemCopyAllInput"/>
                    <MenuItem Header="Copy Selected" Name="MenuItemCopySelectedInput"/>
                    <MenuItem Header="Clear All" Name ="MenuItemClearAllInput"/>
                </ContextMenu>
            </ListView.ContextMenu>
            <ListView.ItemContainerStyle>
                <Style TargetType="{x:Type ListViewItem}">
                    <Setter Property="BorderBrush" Value="LightGray" />
                    <Setter Property="BorderThickness" Value="0,0,0,1" />
                </Style>
            </ListView.ItemContainerStyle>
            <ListView.View>
                <GridView>
                    <GridViewColumn Header="Site Name">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding SiteName}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Site Dial Code">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding SiteDialCode}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="DID Start">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding DIDStart}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="DID End">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding DIDEnd}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="DID Prefix">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding DIDPrefix}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Digits Start">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding DigitsStart}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Digits End">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding DigitsEnd}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Local">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding LocalRange}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Private">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding PrivateRange}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                    <GridViewColumn Header="Main Number">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Label Content = "{Binding MainNumber}"/>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>
                </GridView>
            </ListView.View>
        </ListView>
        <Button x:Name="btnExit" Content="Exit" Margin="553,0,0,14" HorizontalAlignment="Left" Width="93" Height="20" VerticalAlignment="Bottom"/>
        <ScrollViewer HorizontalAlignment="Left" Margin="679,38,0,0" Width="312" VerticalScrollBarVisibility="Auto" Height="643" VerticalAlignment="Top">
            <TextBlock x:Name="txtblockDescription" TextWrapping="Wrap" ScrollViewer.VerticalScrollBarVisibility="Auto" Background="#FFFFFED2" IsManipulationEnabled="True"><Run FontWeight="Bold" Text="INTRODUCTION" TextDecorations="Underline"/><LineBreak/><Run Text="Zach Loeber's DID Normalization Tool serves one primary purpose, to make creation of very specific local and cross site dialing transformations within dial plans as easy as possible. It specifically targeted at Lync deployments with multiple sites wherein each site contains a unique site code and DID ranges with extensions."/><LineBreak/><Run/><LineBreak/><Run Text="This started out as a minor script to help me in what I consider to be a very tedious and unforgiving process. It has since grown to include a number of other ancillary functions which align with the enterprise voice dial plan creation process. If you are going to go through all the trouble of entering in your DID ranges for a site it only makes sense to use that information in other related ways such as:"/><LineBreak/><Run Text=""/><LineBreak/><Run Text="1. Unassigned number range creation"/><LineBreak/><Run Text="2. Starting of a DID management spreadsheet (DID Range Export)."/><LineBreak/><Run/><LineBreak/><Run FontWeight="Bold" Text="FIELDS" TextDecorations="Underline"/><LineBreak/><Run Text="There are a number of fields in this form which may not immediately jive with what you understand to be proper telephony terminology. This is probably because I took some creative liberties in my naming of them! Here is an overview of each of them for your convenience."/><LineBreak/><Run/><LineBreak/><Run FontWeight="Bold" Text="Processing Options"/><LineBreak/><Run Text="These are all related to what happens the moment you click on the 'Generate!' button after having input your DID ranges. None of these options get stored from session to session or with the ranges you add/export/import."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Extension Digit Count" TextDecorations="Underline"/><Run Text=" - This is how many numbers from the end of your DID that are used as your distinguishing extensions. This does NOT include the site code."/><LineBreak/><Run/><LineBreak/><Run Text="If your number is +1 555 666 7777 and your extension digit count is 4 then the local extension for that number is '7777'."/><LineBreak/><Run/><LineBreak/><Run Text="If the site code is '20' then the full telephone URI would be tel:+15556667777;ext=207777"/><LineBreak/><LineBreak/><Run FontStyle="Italic" Text="Simplified Transforms" TextDecorations="Underline"/><Run Text=" - If you check this then the normalization rule will be reduced to matching just the digit count if possible. This is a subtle but important difference in how you transform your digits. Given the following DID range:"/><LineBreak/><Run/><LineBreak/><Run Text="12223335100 - 12223335199"/><LineBreak/><Run/><LineBreak/><Run Text="Simplified transforms would match the following for local 4 digit dialing:"/><LineBreak/><Run/><LineBreak/><Run Text="^(\d{4})$"/><LineBreak/><Run/><LineBreak/><Run Text="Without this option the transform will be far more precise but almost always longer:"/><LineBreak/><Run/><LineBreak/><Run Text="^(51[0-9]{2})$"/><LineBreak/><Run/><LineBreak/><Run Text="If you have lots of normalization rules then you may want to use this option to reduce the overall size of your dial plans for some Lync integrated phones (I'm talking to you VVX series). Otherwise it is best to leave this option unchecked so you get more precise dialing transformations."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Full Extension Transforms" TextDecorations="Underline"/><Run Text=" - Local or cross site transforms normally translate to the full telephone URI. An example might be a user entering 20-5555 (site code 20, extension 5555). This would transform to something like +12223335555. With a full extension transform it would instead transform to +12223335555;ext=205555"/><LineBreak/><Run/><LineBreak/><Run Text="If you are in a situation where there are extensions behind a single dedicated DID then this option will be required for internal calls to normalize and dial correctly so full extension transforms will be done automatically (regardless if this is selected or not)."/><LineBreak/><LineBreak/><Run FontStyle="Italic" Text="Use \d Instead of [0-9] " TextDecorations="Underline"/><Run Text="- If you prefer to see \d instead of [0-9] in your regular expressions then select this option. This also saves you 3 characters I suppose. Thank Ken Lasko for this excellent suggestion!"/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Create Unassigned Ranges" TextDecorations="Underline"/><Run Text=" - If you have not created an unassigned number announcement for your site this is one place you can do so. This is used in the powershell output which should then almost certainly be modified to suit your environment and needs."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Unassigned Number Announcement" TextDecorations="Underline"/><Run Text=" - The text to speech announcement to use for the unassigned ranges configuration."/><LineBreak/><Run/><LineBreak/><Run FontWeight="Bold" Text="Range Export Options"/><LineBreak/><Run Text="These options are specific for creating DID range output suitable for use with excel and manual DID number management."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Do Not Generate Range Export Data" TextDecorations="Underline"/><Run Text=" - If this is selected then the 'Generate!' button will skip over the DID range creation process. This is beneficial for really large number ranges that you may not care so much about tracking. Or maybe you have some fancy pants internal DID tracking solution you use instead. Skipping over the range export creation process can significantly improve processing times."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="AD Matching " TextDecorations="Underline"/><Run Text="- Use this if you want to try and 'match' numbers in your DID range export data with objects in active directory. Without this selected you will only get a blank list of number ranges generated."/><LineBreak/><Run/><LineBreak/><Run Text="If this option is selected then the script will attempt to connect to AD and match up numbers in the DID range to existing common area phones, user accounts, conference numbers, and response groups. If no OU is selected then all of AD is searched. Otherwise the search is restricted to the configuration partition and the selected OU."/><LineBreak/><Run/><LineBreak/><Run FontWeight="Bold" Text="Number Range Input"/><LineBreak/><Run Text="This is where you will enter in all the applicable DID ranges for your sites. "/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Site Name" TextDecorations="Underline"/><Run Text=" - A unique site name. This is used more for the powershell code generation than anything."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Site Code" TextDecorations="Underline"/><Run Text=" - The code used to represent the site if it were to be dialed from other sites. This code is site specific and is required for any intersite dialing transforms to be generated. If this is not supplied then only local site transforms will be created."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="DID Start" TextDecorations="Underline"/><Run Text=" - The start of a DID range for the site. You can (and probably will) have multiple DID ranges per site."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="DID End" TextDecorations="Underline"/><Run Text=" - The end of a DID range for the site. You can (and probably will) have multiple DID ranges per site."/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Local Range" TextDecorations="Underline"/><Run Text=" - Is the range only to be used locally for this site? If so then intersite transforms will be created but not included in powershell code generation for remote sites. This is good for documentation as well."/><LineBreak/><Run/><LineBreak/><Run Text="A big item to be aware of here is that regardless if this range option is selected both the local and intrasite normalization rules will be generated for you (if there is a site code) to use should you need to do so!"/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Private Range" TextDecorations="Underline"/><Run Text=" - If the range is not able to be reached from the outside world then it is a private range. This might be reserved for internal only functions like door buzzers or intercoms. Or it may also be a range that is assigned to users that all share a single public DID. If this is selected you are able to enter a 'Main Number' to associate with it."/><LineBreak/><Run/><LineBreak/><Run Text="A big item to be aware of here is that regardless if this range option is selected both the local and intrasite normalization rules will be generated for you (if there is a site code) to use should you need to do so!"/><LineBreak/><Run/><LineBreak/><Run FontStyle="Italic" Text="Main Number" TextDecorations="Underline"/><Run Text=" - Optionally used with private ranges."/><LineBreak/><Run/><LineBreak/><Run/><LineBreak/><Run FontWeight="Bold" Text="PERSONAL NOTE" TextDecorations="Underline"/><LineBreak/><Run Text="I've found this script to be useful as I don't build a script out unless I have a personal need to fulfill. But my experiences probably do not reflect everyone else's so please provide feedback if you have some time (both negative and positive). There is a link to my blog in this GUI where you can leave comments. Alternatively, reach out to me directly at zloeber@gmail.com and I'll do my best to try and get back to ya."/><LineBreak/><Run/><LineBreak/><Run Text="Zachary Loeber"/></TextBlock>
        </ScrollViewer>
        <Separator Height="22" Margin="22,353,0,0" VerticalAlignment="Top" HorizontalAlignment="Left" Width="603"/>
        <TextBlock HorizontalAlignment="Left" Margin="191,0,0,3.4" TextWrapping="Wrap" Width="154" Height="23" VerticalAlignment="Bottom">
            <Hyperlink x:Name="hyperlinkHome" FontWeight="Black" Foreground="#0066B3" NavigateUri="http://www.the-little-things.net">www.the-little-things.net</Hyperlink>
        </TextBlock>
        <TextBlock HorizontalAlignment="Left" Margin="10,0,0,10.4" TextWrapping="Wrap" Height="16" VerticalAlignment="Bottom">
            <Hyperlink x:Name="hyperlinkGithub" FontWeight="Black" Foreground="#0066B3" NavigateUri="https://github.com/zloeber/Powershell/tree/master/Lync/LyncDIDNormalizer">Github Project Page</Hyperlink>
        </TextBlock>
        <TabControl Height="278" Margin="10,375,0,0" VerticalAlignment="Top" HorizontalAlignment="Left" Width="637">
            <TabItem x:Name="tabTransformations" Header="Transformations" Margin="0,-2,-0.4,0" Height="20" VerticalAlignment="Top">
                <Grid Background="#FFE5E5E5">
                    <ListView x:Name="listviewOutput" Margin="10,41,10.2,9.8" 
                		Grid.IsSharedSizeScope="True">
                        <ListView.ContextMenu>
                            <ContextMenu x:Name="ContextMenuOutput"  StaysOpen="true">
                                <MenuItem Header="Copy All" x:Name="MenuItemCopyAllResults"/>
                                <MenuItem Header="Copy Selected" x:Name="MenuItemCopySelectedResults"/>
                                <MenuItem Header="Clear All" x:Name ="MenuItemClearAllResults"/>
                            </ContextMenu>
                        </ListView.ContextMenu>
                        <ListView.ItemContainerStyle>
                            <Style TargetType="{x:Type ListViewItem}">
                                <Setter Property="BorderBrush" Value="LightGray" />
                                <Setter Property="BorderThickness" Value="0,0,0,1" />
                            </Style>
                        </ListView.ItemContainerStyle>
                        <ListView.View>
                            <GridView>
                                <GridViewColumn Header="Entry Name">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding EntryName}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Transform">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding Transform}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Local Match">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding LocalExt}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Cross Site Match">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding InterSiteExt}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                            </GridView>
                        </ListView.View>
                    </ListView>
                    <Label Content="Turn these into dial plans or caller/calling number transform rules. Or just look at their complex glory!" Margin="10,10,10.2,0" VerticalAlignment="Top" FontWeight="Bold"/>
                </Grid>
            </TabItem>
            <TabItem Header="Exceptions" Margin="0.4,-2,-4.4,0" Height="20" VerticalAlignment="Top">
                <Grid Background="#FFE5E5E5">
                    <ListView x:Name="listviewDIDExceptions" Margin="10,41,10.2,9.8" Grid.IsSharedSizeScope="True">
                        <ListView.ContextMenu>
                            <ContextMenu x:Name="ContextMenuInput1"  StaysOpen="true">
                                <MenuItem Header="Copy All" x:Name="MenuItemCopyAllExceptions"/>
                                <MenuItem Header="Copy Selected" x:Name="MenuItemCopySelectedExceptions"/>
                                <MenuItem Header="Clear All" x:Name ="MenuItemClearAllExceptions"/>
                            </ContextMenu>
                        </ListView.ContextMenu>
                        <ListView.ItemContainerStyle>
                            <Style TargetType="{x:Type ListViewItem}">
                                <Setter Property="BorderBrush" Value="LightGray" />
                                <Setter Property="BorderThickness" Value="0,0,0,1" />
                            </Style>
                        </ListView.ItemContainerStyle>
                        <ListView.View>
                            <GridView>
                                <GridViewColumn Header="Site Name">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding SiteName}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Site Dial Code">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding SiteDialCode}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="DID Start">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding DIDStart}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="DID End">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding DIDEnd}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="DID Prefix">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding DIDPrefix}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Digits Start">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding DigitsStart}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Digits End">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding DigitsEnd}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                            </GridView>
                        </ListView.View>
                    </ListView>
                    <Label Content="Overlapping Ranges You Should Not Use." Margin="10,10,10.2,0" FontWeight="Bold" Height="31" VerticalAlignment="Top"/>
                </Grid>
            </TabItem>
            <TabItem Header="Powershell Output" HorizontalAlignment="Left" Height="20" VerticalAlignment="Top" Width="117" Margin="5.2,-2,-5.4,0">
                <Grid Background="#FFE5E5E5">
                    <ScrollViewer Margin="10,59,10.4,9.8" CanContentScroll="True" VerticalScrollBarVisibility="Auto">
                        <TextBlock x:Name="txtblockExample" TextWrapping="Wrap" Background="#FFE8E2E2" Height="182">
                            <TextBlock.ContextMenu>
                                <ContextMenu StaysOpen="true">
                                    <MenuItem Header="Copy All" x:Name="MenuItemCopyAllExample"/>
                                    <MenuItem Header="Clear All" x:Name ="MenuItemClearAllExample"/>
                                </ContextMenu>
                            </TextBlock.ContextMenu>
                        </TextBlock>
                    </ScrollViewer>
                    <Label Content="Experimental code for creating some of the dial plan rules and unassigned ranges in your environment. &#xD;&#xA;Use this as a baseline for your own code as needed." Margin="10,10,10,0" FontWeight="Bold" Height="44" VerticalAlignment="Top"/>
                </Grid>
            </TabItem>
            <TabItem Header="Range Export Tool" HorizontalAlignment="Left" Height="20" VerticalAlignment="Top" Width="128" Margin="-1.4,-2,0,0">
                <Grid Background="#FFE5E5E5">
                    <ListView x:Name="listviewDIDRangeExport" Margin="10,33,9.2,9.4" Grid.IsSharedSizeScope="True">
                        <ListView.ContextMenu>
                            <ContextMenu x:Name="ContextMenuInput2"  StaysOpen="true">
                                <MenuItem Header="Copy All" x:Name="MenuItemCopyAllDIDRanges"/>
                                <MenuItem Header="Copy Selected" x:Name="MenuItemCopySelectedDIDRanges"/>
                                <MenuItem Header="Clear All" x:Name ="MenuItemClearAllDIDRanges"/>
                            </ContextMenu>
                        </ListView.ContextMenu>
                        <ListView.ItemContainerStyle>
                            <Style TargetType="{x:Type ListViewItem}">
                                <Setter Property="BorderBrush" Value="LightGray" />
                                <Setter Property="BorderThickness" Value="0,0,0,1" />
                            </Style>
                        </ListView.ItemContainerStyle>
                        <ListView.View>
                            <GridView>
                                <GridViewColumn Header="Site">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding SiteName}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Site Code">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding SiteCode}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="LineURI">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding LineURI}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="DDI">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding DDI}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Ext">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding Ext}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Name">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding Name}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="First Name">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding FirstName}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Last Name">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding LastName}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Sip Address">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding SipAddress}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Type">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding Type}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Private">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding Private}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Local">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding Local}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                                <GridViewColumn Header="Notes">
                                    <GridViewColumn.CellTemplate>
                                        <DataTemplate>
                                            <Label Content = "{Binding Notes}"/>
                                        </DataTemplate>
                                    </GridViewColumn.CellTemplate>
                                </GridViewColumn>
                            </GridView>
                        </ListView.View>
                    </ListView>
                    <Label Content="DID Range Export Data. Useful for documentation." Margin="10,2,10.2,0" VerticalAlignment="Top" FontWeight="Bold"/>
                </Grid>
            </TabItem>
        </TabControl>
        <Separator HorizontalAlignment="Left" Margin="335,347,0,0" Width="653" RenderTransformOrigin="0.5,0.5" Height="8" VerticalAlignment="Top">
            <Separator.RenderTransform>
                <TransformGroup>
                    <ScaleTransform/>
                    <SkewTransform/>
                    <RotateTransform Angle="-90.002"/>
                    <TranslateTransform/>
                </TransformGroup>
            </Separator.RenderTransform>
        </Separator>
        <Expander x:Name="expandInstructions" Header="" HorizontalAlignment="Left" Margin="626,351,0,0" VerticalAlignment="Top" IsExpanded="True" RenderTransformOrigin="0.5,0.5" ToolTip="Expand/Collapse Help">
            <Expander.RenderTransform>
                <TransformGroup>
                    <ScaleTransform/>
                    <SkewTransform/>
                    <RotateTransform Angle="88.795"/>
                    <TranslateTransform/>
                </TransformGroup>
            </Expander.RenderTransform>
            <Grid x:Name="ExpanderHelp" Background="#FFE5E5E5"/>
        </Expander>
        <TabControl Height="101" Margin="10,10,0,0" VerticalAlignment="Top" HorizontalAlignment="Left" Width="636">
            <TabItem Header="Processing Options">
                <Grid Background="#FFE5E5E5">
                    <CheckBox x:Name="chkSimplifiedTransforms" Content="Simplified Transforms" HorizontalAlignment="Left" Margin="10,27,0,0" VerticalAlignment="Top" ToolTip="If you check this then normalization rules will be reduced to matching just the number of digits instead of an exact match." Height="16" Width="138" TabIndex="1"/>
                    <CheckBox x:Name="chkUnassignedRanges" Content="Create Unassigned Ranges" Margin="10,48,0,0" VerticalAlignment="Top" ToolTip="Create a basic unassigned DID list" HorizontalAlignment="Left" Width="161" TabIndex="2"/>
                    <TextBlock HorizontalAlignment="Left" Margin="340,8,0,0" TextWrapping="Wrap" VerticalAlignment="Top" Width="246" Height="17"><Run FontWeight="Bold" Text="Unassigned Number Announcement"/></TextBlock>
                    <TextBox x:Name="txtAnnouncement" TextWrapping="Wrap" Text="The number you have called is not assigned to anyone. Please contact the main number for a directory listing." Margin="340,26,10.2,7.8" TabIndex="4"/>
                    <TextBlock HorizontalAlignment="Left" Margin="29,7,0,0" TextWrapping="Wrap" Text="Extension Digit Count" VerticalAlignment="Top" Width="165" Height="17"/>
                    <TextBox x:Name="txtOptionLocalDigits" HorizontalAlignment="Left" Text="4" Width="14" MaxLength="3" Margin="10,8,0,0" TextAlignment="Center" Height="14" VerticalAlignment="Top" IsTabStop="False" ToolTip="Number of digits local site users can call to reach one another." TabIndex="0" RenderTransformOrigin="1.89,0.4" FontSize="10"/>
                    <CheckBox x:Name="chkFullExtensionTransforms" Content="Full Extension Transforms" HorizontalAlignment="Left" Margin="179,27,0,0" VerticalAlignment="Top" ToolTip="Normalization rules will include the ;ext=&lt;extension&gt; portion of the number. If you are using ambiguous ranges then this may not be very beneficial." Height="16" Width="156" TabIndex="3"/>
                    <CheckBox x:Name="chkUseSlashD" Content="Use \d instead of [0-9]" HorizontalAlignment="Left" Margin="179,47,0,0" VerticalAlignment="Top" ToolTip="Use \d instead of [0-9] in generated regular expressions" Height="16" Width="138" TabIndex="4"/>
                </Grid>
            </TabItem>
            <TabItem Header="Range Export Options">
                <Grid Background="#FFE5E5E5">
                    <CheckBox x:Name="chkADMatching" Content="AD Matching" HorizontalAlignment="Left" Margin="10,26,0,0" VerticalAlignment="Top" ToolTip="Attempt to match Full DID URIs against AD." Height="16" Width="109" TabIndex="1"/>
                    <TextBox x:Name="txtOU" TextWrapping="Wrap" Margin="0,0,112.2,4.8" IsEnabled="False" Height="21" VerticalAlignment="Bottom" HorizontalAlignment="Right" Width="407" TabIndex="6"/>
                    <Button x:Name="btnSelectOU" Content="Select OU" HorizontalAlignment="Right" Margin="0,0,524.2,5.8" VerticalAlignment="Bottom" Width="97" IsEnabled="False" Height="21" TabIndex="2"/>
                    <CheckBox x:Name="chkDisableRangeExport" Content="Do Not Generate Range Export Data" HorizontalAlignment="Left" Margin="10,4,0,0" VerticalAlignment="Top" ToolTip="Prevents generation of the DID range export data." Height="16" Width="227" TabIndex="0"/>
                    <Button x:Name="btnGenerateRangeExport" Content="Generate Now" HorizontalAlignment="Left" Margin="524,22.8,0,0" VerticalAlignment="Top" Width="97.2" UseLayoutRounding="False" TabIndex="3"/>
                    <Button x:Name="btnRangeExportADMatch" Content="Match Now" HorizontalAlignment="Left" Margin="524,47.8,0,0" VerticalAlignment="Top" Width="97.2" UseLayoutRounding="False" TabIndex="4"/>
                </Grid>
            </TabItem>
        </TabControl>

    </Grid>
</Window>
'@

# Read XAML
$reader=(New-Object System.Xml.XmlNodeReader $xamlMain) 
$window=[Windows.Markup.XamlReader]::Load( $reader )

$namespace = @{ x = 'http://schemas.microsoft.com/winfx/2006/xaml' }
$xpath_formobjects = "//*[@*[contains(translate(name(.),'n','N'),'Name')]]" 

# Create a variable for every named xaml element
Select-Xml $xamlMain -Namespace $namespace -xpath $xpath_formobjects | Foreach {
    $_.Node | Foreach {
        Set-Variable -Name ($_.Name) -Value $window.FindName($_.Name)
    }
}
#endregion

#region Form Hyperlinks
$hyperlinkHome.add_RequestNavigate({
    start $this.NavigateUri.AbsoluteUri
})

$hyperlinkGithub.add_RequestNavigate({
    start $this.NavigateUri.AbsoluteUri
})
#endregion

#region Form state altering events
$chkPrivateRange.add_Checked({
    Set-FormElementState
})
$chkPrivateRange.add_UnChecked({
    Set-FormElementState
})
$chkADMatching.add_Checked({
    Set-FormElementState
})
$chkADMatching.add_UnChecked({
    Set-FormElementState
})
$expandInstructions.add_Expanded({
    $window.set_Width(1012)
})
$expandInstructions.add_Collapsed({
    $window.set_Width(665)
})
#endregion

#region Individual form element state modifications or changes
$window.add_KeyDown({
    if ($args[1].key -eq 'Return') {
        #Apply changes or whatever else
    }
    elseif ($args[1].key -eq 'Escape') {
        if ((new-popup -message "Exit the application?" -title "Quit?" -Buttons "YesNo") -eq 6) { # 7 = No, 6 = Yes
            $windowMain.Close()
        }
    }
})
$txtLineNumberStart.add_TextChanged({
    $this.Text = $this.Text -replace '\D'
})
$txtLineNumberEnd.add_TextChanged({
    $this.Text = $this.Text -replace '\D'
})
$txtOptionLocalDigits.add_TextChanged({
    $this.Text = $this.Text -replace '\D'
    if ($this.Text -ne '') {
        Reset-FormInputValidationState
        Recalculate-DIDRanges
    }
})
#endregion

#region Context menu (right-click) item actions
$MenuItemClearAllResults.add_Click({
    $listviewOutput.Items.Clear()
})

$MenuItemCopyAllResults.add_Click({
    if ($listviewOutput.Items.Count -gt 0) {
        $OutputItems = $listviewOutput.Items | Select * #EntryName,InterSiteExt,LocalExt,Transform
        Add-Array2Clipboard -ConvertObject  $OutputItems -Header
    }
})

$MenuItemCopySelectedResults.add_Click({
    if ($listviewOutput.Items.Count -gt 0) {
        $OutputItems = $listviewOutput.SelectedItems | Select * #EntryName,InterSiteExt,LocalExt,Transform
        Add-Array2Clipboard -ConvertObject  $OutputItems -Header
    }
})

$MenuItemClearAllExceptions.add_Click({
    $listviewDIDExceptions.Items.Clear()
})

$MenuItemCopyAllExceptions.add_Click({
    if ($listviewDIDExceptions.Items.Count -gt 0) {
        $OutputItems = $listviewDIDExceptions.Items | Select * #SiteName,SiteDialCode,DIDStart,DIDEnd,DIDPrefix,DigitsStart,DigitsEnd
        Add-Array2Clipboard -ConvertObject  $OutputItems -Header
    }
})

$MenuItemCopySelectedExceptions.add_Click({
    if ($listviewDIDExceptions.Items.Count -gt 0) {
        $OutputItems = $listviewDIDExceptions.SelectedItems | Select * #SiteName,SiteDialCode,DIDStart,DIDEnd,DIDPrefix,DigitsStart,DigitsEnd
        Add-Array2Clipboard -ConvertObject  $OutputItems -Header
    }
})

$MenuItemClearAllInput.add_Click({
    $listviewDIDs.Items.Clear()
})

$MenuItemCopyAllInput.add_Click({
    if ($listviewDIDs.Items.Count -gt 0) {
        $InputItems = $listviewDIDs.Items | Select * #SiteName,SiteDialCode,DIDStart,DIDEnd,DIDPrefix,DigitsStart,DigitsEnd
        Add-Array2Clipboard -ConvertObject $InputItems -Header
    }
})

$MenuItemCopySelectedInput.add_Click({
    if ($listviewDIDs.Items.Count -gt 0) {
        $InputItems = $listviewDIDs.SelectedItems | Select * #SiteName,SiteDialCode,DIDStart,DIDEnd,DIDPrefix,DigitsStart,DigitsEnd
        Add-Array2Clipboard -ConvertObject $InputItems -Header
    }
})


$MenuItemClearAllExample.add_Click({
    $txtblockExample.Text = ''
})

$MenuItemCopyAllExample.add_Click({
    Set-Clipboard $txtblockExample.Text
})

$MenuItemClearAllDIDRanges.add_Click({
    $listviewDIDRangeExport.Items.Clear()
})

$MenuItemCopyAllDIDRanges.add_Click({
    if ($listviewDIDRangeExport.Items.Count -gt 0) {
        $InputItems = $listviewDIDRangeExport.Items | Select *
        Add-Array2Clipboard -ConvertObject $InputItems -Header
    }
})

$MenuItemCopySelectedDIDRanges.add_Click({
    if ($listviewDIDRangeExport.Items.Count -gt 0) {
        $InputItems = $listviewDIDRangeExport.SelectedItems | Select *
        Add-Array2Clipboard -ConvertObject $InputItems -Header
    }
})
#endregion

#region Buttons, buttons, buttons!
$btnExit.add_Click({
    if ((new-popup -message "Exit the application?" -title "Quit?" -Buttons "YesNo") -eq 6) {
        $windowMain.Close()
    }
})

$btnLoad.add_Click({
    $filename = Get-FileFromDialog -fileFilter 'CSV file (*.csv)|*.csv' -titleDialog "Select A CSV File:"
    if (($filename -ne '') -and (Test-Path $filename)) {
        $ImportData = Import-Csv $filename
        $HasAllColumns = $true
        $test = $ImportData[0]

        $InputProperties | Foreach {
            if (-not $test.PSObject.Properties.Match($_).Count) {
                $HasAllColumns = $false
            }
        }

        if ($HasAllColumns) {
            $listviewOutput.Items.Clear()
            $listviewDIDs.Items.Clear()
            $listviewDIDExceptions.Items.Clear()
            $ImportData | Foreach { 
                $listviewDIDs.Items.Add($_)
            }
            Reset-FormInputValidationState
        }
        else {
            New-Popup -Title 'Whoops!' -Message 'Missing columns from source data preventing the list from loading'
        }
    }
    
})
$btnSaveInput.add_Click({
    $filename = Save-FileFromDialog -defaultfilename 'did-backup.csv' -titleDialog 'Backup to a CSV file:' -fileFilter 'CSV file (*.csv)|*.csv'
    if ($filename -ne $null) {
        $listviewDIDs.Items | Export-Csv $filename -NoTypeInformation
    }
})
$btnSelectOU.add_Click({
    $OU = Get-OUDialog
    if (($OU -ne $null) -and ($OU -ne '')) {
        $txtSelectedOU.Text = $OU
    }
})
$btnAdd.add_Click({
    if (Set-FormInputValidationState) {
        $Digits = $txtOptionLocalDigits.text
        $DIDStart = $txtLineNumberStart.Text
        $DIDEnd = $txtLineNumberEnd.Text
        if (((($DIDStart).length - $Digits) -ge 0) -and ((($DIDEnd).length - $Digits) -ge 0)) {
            $DigitsStart = ($DIDStart).substring(($DIDStart).length - $Digits, $Digits)
            $DigitsEnd = ($DIDEnd).substring(($DIDEnd).length - $Digits, $Digits)
            if ($chkPrivateRange.IsChecked) {
                $PrefixStart = ''
            }
            else {
                $PrefixStart = ($DIDStart).substring(0,($DIDStart).length - $Digits)
            }
            $PrefixEnd = ($DIDEnd).substring(0,($DIDEnd).length - $Digits)
            if ($PrefixStart -eq $PrefixEnd) {
                $tmpObj = New-Object psobject -Property @{
                    'SiteName' = $txtSiteName.Text
                    'SiteDialCode' = $txtSiteDialCode.Text
                    'DIDStart' = $txtLineNumberStart.Text
                    'DIDEnd' = $txtLineNumberEnd.Text
                    'DIDPrefix' = $PrefixStart
                    'DigitsStart' = $DigitsStart
                    'DigitsEnd' = $DigitsEnd
                    'PrivateRange' = $chkPrivateRange.IsChecked
                    'LocalRange' = $chkLocalRange.IsChecked
                    'MainNumber' = if ($txtMainNumber.IsEnabled) {$txtMainNumber.Text} else {''}
                }
                $listviewDIDs.Items.Add($tmpObj)
                Reset-FormInputValidationState
            }
            else {
                $txtOptionLocalDigits.BorderThickness=2
                $txtOptionLocalDigits.BorderBrush='#FFF21A11'
                $txtOptionLocalDigits.Tooltip = 'This digit length would result in multiple (thus ambiguous) DID prefixes! To use this digit length please split this DID range so that all unique prefixes are in their own range.'
            }
        }
        else {
            $txtOptionLocalDigits.BorderThickness=2
            $txtOptionLocalDigits.BorderBrush='#FFF21A11'
            $txtOptionLocalDigits.Tooltip= 'This digit length is greater than your DID size!'
        }
    }
})
$btnRemove.add_Click({
    if (($listviewDIDs.Items.Count -gt 0) -and ($listviewDIDs.SelectedIndex -ge 0)) {
        $listviewDIDs.Items.RemoveAt($listviewDIDs.SelectedIndex)
    }
})

$btnGenerate.add_Click({
    if (Validate-LocalDigitLength) {
        # Start from a clean slate
        Clear-ListBoxes
        
        # Gather all our ranges for processing
        $tempDIDs = @()
        foreach ($item in $listviewDIDs.Items) {
            # Add a distinguishing property to filter out duplicates
            $tmpObj = $item.PsObject.Copy()
            $tmpObj | Add-Member -MemberType NoteProperty -Name FullRange -Value ($item.MainNumber + $item.DIDStart + '-' + $item.MainNumber + $item.DIDEnd)
            $tmpObj.LocalRange = ($tmpObj.LocalRange -eq 'TRUE')
            $tmpObj.PrivateRange = ($tmpObj.PrivateRange -eq 'TRUE')
            $tempDIDs += $tmpObj
        }

        # assuming we have stuff to work with then sort them out and process the entries by site code
        if ($tempDIDs.Count -gt 0) {
            $listviewDIDExceptions.Items.Clear()
            $listviewOutput.Items.Clear()
            $SiteCodes = $tempDIDs.SiteDialCode | Select -Unique
            $CreateDialPlans = "# Create per-site dial plans`t`n"
            $LocalDialPlanNormRules = "# Add local site dialling normalization rules to the dial plans`t`n"
            $IntersiteDialPlanNormRules = "# Add Intersite dialling normalization rules to the dial plans`t`n"
            #$GlobalDialPlanNormRules = "# Add Global dialling normalization rules to the dial plans`t`n"
            $RemoveNormRules = "# Remove the catch all normalization rules (optional)`t`n"
            $AddNormRules = "# Re-add the catch all normalization rules so they end up last in the list`t`n"
            $UnassignedRanges = ""
            $SiteNorms = @{}
            $DupeDIDRanges = @()
            foreach ($Site in $SiteCodes) {
                $TempIntersiteDialPlanNormRules = ''
                $NormCount = 1
                $SiteName = ($tempDIDs | Where {$_.SiteDialCode -eq $Site}).SiteName | Select -Unique
                $CreateDialPlans += "New-CsDialPlan -Identity `'$SiteName`'`t`n"
                $SiteDIDs = @($tempDIDs | Where {$_.SiteDialCode -eq $Site} | Sort-Object -Property DIDStart | Select-Unique -Property FullRange)
                
                # build up our unassigned ranges commands if applicable
                if ($chkUnassignedRanges.isChecked) {
                    $UnassignedCount = 1
                    $SiteDIDs | Foreach {
                        $UnassignedRanges += $NewCsUnassignedRange -replace '<sitename>',$_.SiteName `
                                                                   -replace '<count>',$UnassignedCount `
                                                                   -replace '<rangestart>',$_.DIDStart `
                                                                   -replace '<rangeend>',$_.DIDEnd
                        $UnassignedRanges += "`n"
                        $UnassignedCount++
                    }
                }
                
                if ($SiteDIDs.Count -gt 1) {
                    # Get any overlaps in all our ranges
                    $SplitDIDRanges = @(Get-SiteDialPlanOverlaps -Obj $SiteDIDs -Digits $txtOptionLocalDigits.text)
                }
                else {
                    $SplitDIDRanges = $SiteDIDs
                }
                $DupeDIDRangeSets = $SplitDIDRanges | Where {$_.Overlapped}
                $WorkingDIDRanges = @($SplitDIDRanges | Where {-not $_.Overlapped})
                
                Foreach ($DupeIndex in ($DupeDIDRangeSets.Index | Select -Unique)) {
                    $DupProps = (($DupeDIDRangeSets[0]).psobject.Properties | where {$_.MemberType -eq 'NoteProperty'}).Name

                    $DupeSet = $DupeDIDRangeSets | Where {$_.Index -eq $DupeIndex} | Select $DupProps
                    $DupeDIDRanges += $DupeSet[0]
                    $WorkingDIDRanges += $DupeSet[1]
                }
                
                $Transforms = @()
                
#                # If we have simplified transforms selected and only one DID prefix then create transforms with just the digit count
#                # Note: This needs work....
#                if (($chkSimplifiedTransforms.IsChecked) -and ((($WorkingDIDRanges).DIDPrefix | Select -Unique).Count -eq 1)) {
#                    $Transforms += New-Object psobject -Property @{
#                        'EntryName' = $WorkingDIDRanges[0].SiteName +'-' + $txtOptionLocalDigits.text
#                        'LocalExt' = '^(\d{' + $txtOptionLocalDigits.text + '})$'
#                        'InterSiteExt' = '^(' + ($WorkingDIDRanges[0]).SiteDialCode + '\d{' + $txtOptionLocalDigits.text + '})$'
#                        'Transform' = '+' + ($WorkingDIDRanges[0]).DIDPrefix + '$1'
#                        'LocalRange' = ($WorkingDIDRanges[0]).LocalRange
#                    }
#                }
#                else {
                $Transforms += $WorkingDIDRanges | New-SiteDialPlanTransform -Digits $txtOptionLocalDigits.text -SimplifiedTransforms $chkSimplifiedTransforms.IsChecked
                if ($chkUseSlashD.IsChecked) {
                    $Transforms | Foreach {
                        [string]$tmpLocalExt = $_.LocalExt
                        [string]$tmpInterSiteExt = $_.InterSiteExt
                        $_.LocalExt = $tmpLocalExt.Replace('[0-9]','\d')
                        $_.InterSiteExt = $tmpInterSiteExt.Replace('[0-9]','\d')
                    }
                }
#                }

                $TotalDigitCount = [int]($txtOptionLocalDigits.text) + (($WorkingDIDRanges[0]).SiteDialCode).length
                
                # Create the posh commands for the local site dial plan normalization rules
                $Transforms | Foreach {
                    $LocalDialPlanNormRules += $NewNormRuleLocal -replace '<0>',$SiteName `
                                                             -replace '<1>',$NormCount `
                                                             -replace '<2>',$txtOptionLocalDigits.text `
                                                             -replace '<3>',$_.LocalExt `
                                                             -replace '<4>',$_.Transform
                    $LocalDialPlanNormRules += "`n"
                    $LocalDialPlanNormRules += $NewNormRuleLocal -replace '<0>',$SiteName `
                                                             -replace '<1>',$NormCount `
                                                             -replace '<2>',$TotalDigitCount `
                                                             -replace '<3>',$_.InterSiteExt `
                                                             -replace '<4>',$_.Transform
                    $LocalDialPlanNormRules += "`n"
                    # Create normalization rules for intersite dialling
                    if (($_.InterSiteExt -ne '') -and ($_.InterSiteExt -ne $null) -and (-not $_.LocalRange)) {
                        $TempIntersiteDialPlanNormRules += $NewNormRuleInterSite -replace '<0>',$SiteName `
                                                                             -replace '<1>',$NormCount `
                                                                             -replace '<2>',$_.InterSiteExt `
                                                                             -replace '<3>',$_.Transform `
                                                                             -replace '<4>',$TotalDigitCount
                        $TempIntersiteDialPlanNormRules += "`n"
                    }                                                 
                    $listviewOutput.Items.Add($_)
                    $NormCount++
                }
                if ($TempIntersiteDialPlanNormRules -ne '') {
                    # Keep a hash of intersite normalization rules for later
                    $SiteNorms.$SiteName = $TempIntersiteDialPlanNormRules
                }

                $AddNormRules = "# Re-add the catch all normalization rules so they end up last in the list`t`n"
            }
            
            # Create the intersite normalizations
            ForEach ($Site in ($tempDIDs.SiteName | Select -Unique)) {
                $SiteNorms.Keys | Foreach {
                    $IntersiteDialPlanNormRules += $SiteNorms.$_ -replace '<parent>',$Site
                }
                #$GlobalDialPlanNormRules += $SiteNorms.$Site -replace '<parent>','Global'
                $RemoveNormRules += $RemoveNormRuleKeepAll -replace '<parent>',$Site
                $RemoveNormRules += "`n"
                $AddNormRules += $AddNormRuleKeepAll -replace '<parent>',$Site
                $AddNormRules += "`n"
            }
            
            # Display our powershell output
            $txtblockExample.text = $CreateDialPlans + "`n" + `
                                    $LocalDialPlanNormRules + "`n" + `
                                    $RemoveNormRules + "`n" + `
                                    $IntersiteDialPlanNormRules + "`n" + `
                                    $AddNormRules + "`n" # + `
                                    #$GlobalDialPlanNormRules + "`n"
            
            # Add unassigned ranges and announcements
            if ($chkUnassignedRanges.isChecked) {
                $NewCsAnnouncement = $NewAnnouncementTemplate -replace '<prompt>',$txtAnnouncement.Text
                $txtblockExample.text = $txtblockExample.text + "`n" + `
                                        $NewCsAnnouncement + "`n" + `
                                        ($NewCsUnassignedTemplate -replace '<unassignedranges>',$UnassignedRanges)
                                        
                                        
            }
            $DupeDIDRanges | Foreach {$listviewDIDExceptions.Items.Add($_)}
            
            # Now lets create our DID range export data
            Generate-DIDRangeExport
        }
    }
})
$btnGenerateRangeExport.add_Click({
    Generate-DIDRangeExport 
})
$btnRangeExportADMatch.add_Click({

})
#endregion

#region Main

# Set initial form controls state (enabled/disabled/et cetera) 
Set-FormElementState

# Show the dialog
# Due to some bizarre bug with showdialog and xaml we need to invoke this asynchronously to prevent a segfault
$async = $windowMain.Dispatcher.InvokeAsync({
    $windowMain.ShowDialog() | Out-Null
})
$async.Wait() | Out-Null

# Clear out previously created variables for every named xaml element to be nice...
Select-Xml $xamlMain -Namespace $namespace -xpath $xpath_formobjects | Foreach {
    $_.Node | Foreach {
        Remove-Variable -Name ($_.Name)
    }
}
#endregion