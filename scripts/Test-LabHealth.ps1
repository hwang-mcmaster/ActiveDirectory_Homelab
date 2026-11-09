[CmdletBinding()]
param([string]$ConfigPath)
$ErrorActionPreference='Stop'
if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot '../config/lab.example.json' }
Import-Module "$PSScriptRoot/../src/LabLifecycle/LabLifecycle.psd1" -Force
$c=Read-LabConfig $ConfigPath
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop
$checks=New-Object System.Collections.Generic.List[object]
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; $checks.Add([pscustomobject]@{Check=$Name;Passed=$true}) }
    catch { $checks.Add([pscustomobject]@{Check=$Name;Passed=$false}); Write-Warning "$Name failed; inspect the relevant service locally." }
}
Check 'Domain identity' { $d=Get-ADDomain -Server $c.Server; if($d.DNSRoot -ine $c.DomainName){throw 'Mismatch'} }
Check 'LDAP SRV DNS' { $records=@(Resolve-DnsName "_ldap._tcp.dc._msdcs.$($c.DomainName)" -Type SRV -Server $c.Server -ErrorAction Stop); if(-not ($records | Where-Object Type -EQ SRV)){throw 'No SRV records'} }
Check 'Lifecycle OUs' { foreach($dn in @($c.UsersOU,$c.DisabledOU,$c.GroupsOU,$c.ComputersOU)){ Get-ADOrganizationalUnit -Identity $dn -Server $c.Server -ErrorAction Stop | Out-Null } }
Check 'Workstation GPO link' { $links=(Get-GPInheritance -Target $c.ComputersOU -Domain $c.DomainName -Server $c.Server).GpoLinks; if('LAB-Workstation-Lock' -notin @($links | Select-Object -ExpandProperty DisplayName)){throw 'Link absent'} }
$checks
if (@($checks | Where-Object { -not $_.Passed }).Count -gt 0) { throw 'Lab health checks failed.' }
