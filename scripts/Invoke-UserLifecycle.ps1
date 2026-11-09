[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][ValidateSet('Onboard','Offboard')][string]$Action,
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$ConfigPath,
    [string]$AuditPath,
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '../config/lab.example.json' }
if (-not $AuditPath) { $AuditPath = Join-Path $PSScriptRoot '../logs/lifecycle.jsonl' }
Import-Module "$PSScriptRoot/../src/LabLifecycle/LabLifecycle.psd1" -Force
$argsMap = @{Action=$Action; CsvPath=$CsvPath; ConfigPath=$ConfigPath; AuditPath=$AuditPath; Apply=$Apply}
foreach ($key in @('WhatIf','Confirm')) { if ($PSBoundParameters.ContainsKey($key)) { $argsMap[$key]=$PSBoundParameters[$key] } }
Invoke-LabLifecycle @argsMap
