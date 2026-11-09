[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([string]$ConfigPath,[switch]$Apply)
$ErrorActionPreference='Stop'
if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot '../config/lab.example.json' }
Import-Module "$PSScriptRoot/../src/LabLifecycle/LabLifecycle.psd1" -Force
$c=Read-LabConfig $ConfigPath
if ($c.NetbiosName -notmatch '^[A-Z][A-Z0-9]{0,14}$') { throw 'Invalid NetBIOS name.' }
if (-not $Apply) { "Plan: install AD DS/DNS and create $($c.DomainName) on the DC01 Windows Server guest. Reboot required afterward."; return }
$os=Get-CimInstance Win32_OperatingSystem
$cs=Get-CimInstance Win32_ComputerSystem
if ($os.ProductType -ne 3 -or $cs.Name -ine 'DC01' -or $cs.PartOfDomain) { throw 'Run only on a standalone Windows Server guest named DC01, never on the physical host.' }
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run as administrator inside DC01.' }
if ($PSCmdlet.ShouldProcess("DC01 / $($c.DomainName)",'Install AD DS/DNS and create a new forest')) {
    $dsrm=Read-Host 'Enter a unique DSRM recovery password (store it securely)' -AsSecureString
    $result=Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
    if (-not $result.Success) { throw 'AD DS role installation failed.' }
    Import-Module ADDSDeployment -ErrorAction Stop
    Install-ADDSForest -DomainName $c.DomainName -DomainNetbiosName $c.NetbiosName -InstallDNS -SafeModeAdministratorPassword $dsrm -NoRebootOnCompletion:$true -Force -ErrorAction Stop
    'Forest installation command completed. Reboot DC01 manually, then verify DNS and AD before continuing.'
}
