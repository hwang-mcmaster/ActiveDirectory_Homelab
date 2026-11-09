[CmdletBinding()]
param([switch]$SkipTests)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$failures=New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $repo -Recurse -File | Where-Object { $_.Extension -in '.ps1','.psm1','.psd1' } | ForEach-Object {
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    foreach($e in $errors){$failures.Add("$($_.Name): $($e.Message)")}
}
if($failures.Count){throw ($failures -join [Environment]::NewLine)}
Import-Module "$repo/src/LabLifecycle/LabLifecycle.psd1" -Force
$c=Read-LabConfig "$repo/config/lab.example.json"
foreach($action in @('Onboard','Offboard')) {
    $file=if($action -eq 'Onboard'){'onboarding'}else{'offboarding'}
    Read-LifecycleCsv "$repo/data/$file.example.csv" $c $action | Out-Null
}
Remove-Module LabLifecycle
if(-not $SkipTests) {
    $available=Get-Module -ListAvailable Pester | Where-Object Version -GE '5.7.1' | Sort-Object Version -Descending | Select-Object -First 1
    if(-not $available){throw 'Install Pester 5.7.1 or later (CurrentUser); the bundled Pester 3 is not supported.'}
    Import-Module $available.Path -Force
    $testConfig=New-PesterConfiguration
    $testConfig.Run.Path="$repo/tests"
    $testConfig.Run.PassThru=$true
    $testConfig.TestRegistry.Enabled=$false
    $r=Invoke-Pester -Configuration $testConfig
    if($r.FailedCount -gt 0 -or $r.PassedCount -eq 0){throw "Tests failed: $($r.FailedCount); passed: $($r.PassedCount)"}
    "Pester: $($r.PassedCount) passed, $($r.FailedCount) failed."
}
'Repository parsing and example validation passed.'
