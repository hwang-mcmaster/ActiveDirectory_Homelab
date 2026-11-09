[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([string]$ConfigPath,[switch]$Apply)
$ErrorActionPreference='Stop'
if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot '../config/lab.example.json' }
Import-Module "$PSScriptRoot/../src/LabLifecycle/LabLifecycle.psd1" -Force
$c=Read-LabConfig $ConfigPath
if (-not $Apply) { "Plan: create protected Lab/Users/Disabled/Groups/Workstations OUs, flat approved groups, workstation screen-lock GPO on $($c.Server)."; return }
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop
$ad=@{Server=$c.Server;ErrorAction='Stop'}
$d=Get-ADDomain @ad
if ($d.DNSRoot -ine $c.DomainName -or $d.DistinguishedName -ine $c.BaseDN) { throw 'Wrong domain.' }
if ($PSCmdlet.ShouldProcess($c.DomainName,'Initialize lab OUs, groups and workstation GPO')) {
    foreach ($dn in @($c.LabOU,$c.UsersOU,$c.DisabledOU,$c.GroupsOU,$c.ComputersOU)) {
        $existing = @(Get-ADOrganizationalUnit -Filter * -SearchBase $c.BaseDN @ad | Where-Object DistinguishedName -EQ $dn)
        if ($existing.Count -eq 0) {
            $name=$dn.Split(',')[0].Substring(3); $parent=$dn.Substring($dn.IndexOf(',')+1)
            New-ADOrganizationalUnit -Name $name -Path $parent -ProtectedFromAccidentalDeletion $true @ad
        }
    }
    foreach ($name in $c.AllowedGroups) {
        $existing = @(Get-ADGroup -Filter "SamAccountName -eq '$name'" @ad)
        if ($existing.Count -eq 0) { New-ADGroup -Name $name -SamAccountName $name -GroupScope Global -GroupCategory Security -Path $c.GroupsOU @ad }
        elseif (-not $existing[0].DistinguishedName.EndsWith(",$($c.GroupsOU)",[StringComparison]::OrdinalIgnoreCase)) { throw "Group collision: $name" }
    }
    $gpoName='LAB-Workstation-Lock'
    $gpo=Get-GPO -All -Domain $c.DomainName -Server $c.Server | Where-Object DisplayName -EQ $gpoName
    if (-not $gpo) { $gpo=New-GPO -Name $gpoName -Domain $c.DomainName -Server $c.Server }
    Set-GPRegistryValue -Guid $gpo.Id -Domain $c.DomainName -Server $c.Server -Key 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System' -ValueName InactivityTimeoutSecs -Type DWord -Value 900 | Out-Null
    $links=(Get-GPInheritance -Target $c.ComputersOU -Domain $c.DomainName -Server $c.Server).GpoLinks
    if ($gpo.Id -notin @($links | Select-Object -ExpandProperty GpoId)) { New-GPLink -Guid $gpo.Id -Target $c.ComputersOU -Domain $c.DomainName -Server $c.Server -LinkEnabled Yes | Out-Null }
}
