Describe 'Infrastructure offline plans' {
    BeforeAll { $script:repo=Split-Path -Parent $PSScriptRoot }
    It 'plans a powered-off VM without Hyper-V or ISO access' {
        $plan=& "$script:repo/scripts/New-LabVM.ps1" -Name LAB-DC01 -Root 'D:\SysadminLab' -IsoPath 'D:\ISO\not-present.iso'
        $plan.Mode | Should -Be 'OfflinePlan'
        $plan.PowerState | Should -Be 'Off'
        $plan.VM | Should -Be 'LAB-DC01'
    }
    It 'rejects an unapproved VM name' {
        { & "$script:repo/scripts/New-LabVM.ps1" -Name ProductionVM } | Should -Throw
    }
    It 'rejects a drive root as VM storage' {
        { & "$script:repo/scripts/New-LabVM.ps1" -Name LAB-DC01 -Root 'C:\' } | Should -Throw
    }
    It 'rejects relative VM storage' {
        { & "$script:repo/scripts/New-LabVM.ps1" -Name LAB-DC01 -Root '..\VMs' } | Should -Throw
    }
    It 'rejects out-of-range VM memory' {
        { & "$script:repo/scripts/New-LabVM.ps1" -Name LAB-CL01 -MemoryGiB 1 } | Should -Throw
    }
    It 'refuses applying a nonexistent installer before touching Hyper-V' {
        { & "$script:repo/scripts/New-LabVM.ps1" -Name LAB-DC01 -IsoPath "$TestDrive/absent.iso" -Apply -Confirm:$false } | Should -Throw
    }
    It 'plans forest installation without probing or changing the host' {
        & "$script:repo/scripts/Install-LabForest.ps1" | Should -Match 'Plan:.*DC01'
    }
    It 'plans OU and GPO initialization without AD access' {
        & "$script:repo/scripts/Initialize-LabDirectory.ps1" | Should -Match 'Plan:.*GPO'
    }
    It 'runs the Windows PowerShell CLI with script-relative config defaults' {
        $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script:repo/scripts/Invoke-UserLifecycle.ps1" -Action Onboard -CsvPath "$script:repo/data/onboarding.example.csv" 2>&1
        $LASTEXITCODE | Should -Be 0
        ($output -join [Environment]::NewLine) | Should -Match 'OfflinePlan'
    }
}
