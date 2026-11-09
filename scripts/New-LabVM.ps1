[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [ValidateSet('LAB-DC01','LAB-CL01','LAB-FS01')][string]$Name,
    [ValidateRange(2,16)][int]$MemoryGiB = 4,
    [ValidateRange(1,8)][int]$CpuCount = 2,
    [ValidateRange(64,256)][int]$DiskGiB = 64,
    [string]$Root = 'D:\SysadminLab',
    [string]$IsoPath,
    [string]$SwitchName = 'SysadminLab-Private',
    [switch]$Apply,
    [switch]$FromTerraform
)
$ErrorActionPreference = 'Stop'
if ($FromTerraform) {
    if (-not $env:LAB_VM_SPEC) { throw 'LAB_VM_SPEC is required.' }
    $spec = $env:LAB_VM_SPEC | ConvertFrom-Json
    # Re-enter parameter binding to validate environment-supplied values.
    & $PSCommandPath -Name $spec.name -MemoryGiB $spec.memory_gib -CpuCount $spec.cpu_count -DiskGiB $spec.disk_gib -Root $spec.root -IsoPath $spec.iso -SwitchName $spec.switch_name -Apply -Confirm:$false
    return
}
if (-not $Name) { throw 'Name is required.' }
if (-not [IO.Path]::IsPathRooted($Root) -or $Root -notmatch '^[A-Za-z]:\\' -or $Root -match '\.\.') { throw 'Root must be an absolute local drive path without parent traversal.' }
$rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
if ($rootPath -match '^[A-Za-z]:$') { throw 'Use a dedicated subdirectory, not a drive root.' }
$vmPath = Join-Path $rootPath $Name
$diskPath = Join-Path $vmPath 'os.vhdx'
if (-not $Apply) {
    [pscustomobject]@{Mode='OfflinePlan'; VM=$Name; MemoryGiB=$MemoryGiB; CpuCount=$CpuCount; DiskGiB=$DiskGiB; Path=$vmPath; Switch=$SwitchName; ISO=$IsoPath; PowerState='Off'}
    return
}
if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf) -or [IO.Path]::GetExtension($IsoPath) -ine '.iso') { throw 'Provide an existing Windows installer ISO.' }
Import-Module Hyper-V -ErrorAction Stop
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction Stop
if ($switch.SwitchType -ne 'Private') { throw 'Use a dedicated Private switch to isolate the AD lab.' }
if (@(Get-VM -ErrorAction Stop | Where-Object Name -EQ $Name).Count -gt 0) { throw 'VM already exists. Refusing to adopt or overwrite; inspect it manually.' }
if (Test-Path -LiteralPath $vmPath) { throw 'VM directory already exists; inspect partial deployment before retrying.' }
if ($PSCmdlet.ShouldProcess($Name, 'Create powered-off Generation 2 Hyper-V VM')) {
    New-Item -ItemType Directory -Path $vmPath | Out-Null
    New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryGiB * 1GB) -Path $vmPath -NewVHDPath $diskPath -NewVHDSizeBytes ($DiskGiB * 1GB) -SwitchName $SwitchName -ErrorAction Stop | Out-Null
    Set-VM -Name $Name -ProcessorCount $CpuCount -AutomaticStartAction Nothing -AutomaticStopAction ShutDown -AutomaticCheckpointsEnabled $false -Notes 'Sysadmin portfolio lab; managed creation only; no automatic deletion.' -ErrorAction Stop
    Add-VMDvdDrive -VMName $Name -Path $IsoPath -ErrorAction Stop
    $dvd = Get-VMDvdDrive -VMName $Name -ErrorAction Stop
    Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows -FirstBootDevice $dvd -ErrorAction Stop
    if ($Name -eq 'LAB-CL01') {
        Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector -ErrorAction Stop
        Enable-VMTPM -VMName $Name -ErrorAction Stop
    }
    Get-VM -Name $Name | Select-Object Name,State,Generation,ProcessorCount,MemoryStartup
}
