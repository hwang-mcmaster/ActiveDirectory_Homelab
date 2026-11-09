[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$report = [ordered]@{
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    PowerShell = $PSVersionTable.PSVersion.ToString()
    IsAdministrator = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    HyperVModule = [bool](Get-Module -ListAvailable Hyper-V)
    ADModule = [bool](Get-Module -ListAvailable ActiveDirectory)
    Terraform = [bool](Get-Command terraform -ErrorAction SilentlyContinue)
    Git = [bool](Get-Command git -ErrorAction SilentlyContinue)
}
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $report.OS = $os.Caption
    $report.RAMGiB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $report.HypervisorPresent = $cs.HypervisorPresent
} catch { $report.HardwareProbe = 'Unavailable: run locally with sufficient read permissions.' }
if ($report.HyperVModule) {
    try { $report.Switches = @(Get-VMSwitch | Select-Object Name,SwitchType) }
    catch { $report.SwitchProbe = 'Unavailable: Hyper-V administrative access required.' }
}
[pscustomobject]$report
