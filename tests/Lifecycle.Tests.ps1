Describe 'Lab lifecycle suite' {
BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module "$repo/src/LabLifecycle/LabLifecycle.psd1" -Force
    $global:LabTestRepo = $repo
    # Local AD-shaped command stubs let mocks run without RSAT or a domain.
    # Every stub throws if a test accidentally falls through to it.
    & (Get-Module LabLifecycle) {
        foreach ($name in @('Get-ADDomain','Get-ADOrganizationalUnit','Get-ADGroup','Get-ADPrincipalGroupMembership','Get-ADUser','Get-ADGroupMember','New-ADUser','Set-ADUser','Add-ADGroupMember','Disable-ADAccount','Set-ADAccountPassword','Remove-ADGroupMember','Move-ADObject')) {
            Set-Item "Function:script:$name" -Value {
                [CmdletBinding(SupportsShouldProcess)]
                param($Identity,$Filter,$Properties,$Server,$Name,$SamAccountName,$UserPrincipalName,$GivenName,$Surname,$EmployeeID,$Department,$Path,$Enabled,$AccountPassword,$Members,$NewPassword,$TargetPath,[switch]$Reset)
                throw 'Unmocked AD command: tests must never contact AD.'
            }
        }
    }
}

Context 'CSV and configuration safety' {
    BeforeEach {
        $script:config = Read-LabConfig "$global:LabTestRepo/config/lab.example.json"
    }
    It 'accepts the example onboarding batch' {
        @(Read-LifecycleCsv "$global:LabTestRepo/data/onboarding.example.csv" $script:config Onboard).Count | Should -Be 2
    }
    It 'accepts the example offboarding batch' {
        @(Read-LifecycleCsv "$global:LabTestRepo/data/offboarding.example.csv" $script:config Offboard).Count | Should -Be 1
    }
    It 'rejects duplicate accounts before any AD access' {
        @('SamAccountName,EmployeeID','alice.chen,LAB001','alice.chen,LAB002') | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Offboard } | Should -Throw
    }
    It 'rejects duplicate employee IDs' {
        @('SamAccountName,EmployeeID','alice.chen,LAB001','ben.patel,LAB001') | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Offboard } | Should -Throw
    }
    It 'rejects filter injection in usernames' {
        @('SamAccountName,EmployeeID',"a' -or name -like '*,LAB001") | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Offboard } | Should -Throw
    }
    It 'rejects built-in accounts' {
        @('SamAccountName,EmployeeID','Administrator,LAB001') | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Offboard } | Should -Throw
    }
    It 'rejects missing headers' {
        @('SamAccountName','alice.chen') | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Offboard } | Should -Throw
    }
    It 'rejects empty batches' {
        'SamAccountName,EmployeeID' | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Offboard } | Should -Throw
    }
    It 'enforces the batch limit' {
        $script:config.MaxBatchSize=1
        { Read-LifecycleCsv "$global:LabTestRepo/data/onboarding.example.csv" $script:config Onboard } | Should -Throw
    }
    It 'rejects unapproved groups' {
        (Get-Content "$global:LabTestRepo/data/onboarding.example.csv") -replace 'LAB-IT','Domain Admins' | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Onboard } | Should -Throw
    }
    It 'rejects unapproved departments' {
        (Get-Content "$global:LabTestRepo/data/onboarding.example.csv") -replace ',IT,',',Unknown,' | Set-Content "$TestDrive/input.csv"
        { Read-LifecycleCsv "$TestDrive/input.csv" $script:config Onboard } | Should -Throw
    }
    It 'rejects a base DN that disagrees with the domain' {
        $script:config.BaseDN='DC=other,DC=test'
        $script:config | ConvertTo-Json | Set-Content "$TestDrive/config.json"
        { Read-LabConfig "$TestDrive/config.json" } | Should -Throw
    }
    It 'rejects an OU outside the lab boundary' {
        $script:config.UsersOU=$script:config.BaseDN
        $script:config | ConvertTo-Json | Set-Content "$TestDrive/config.json"
        { Read-LabConfig "$TestDrive/config.json" } | Should -Throw
    }
    It 'rejects groups without the LAB prefix' {
        $script:config.AllowedGroups=@('Domain Admins')
        $script:config | ConvertTo-Json | Set-Content "$TestDrive/config.json"
        { Read-LabConfig "$TestDrive/config.json" } | Should -Throw
    }
    It 'produces a default offline plan without AD or audit writes' {
        $result=@(Invoke-LabLifecycle -ConfigPath "$global:LabTestRepo/config/lab.example.json" -CsvPath "$global:LabTestRepo/data/onboarding.example.csv" -Action Onboard -AuditPath "$TestDrive/noaudit.jsonl")
        $result.Count | Should -Be 2
        $result[0].Mode | Should -Be 'OfflinePlan'
        Test-Path "$TestDrive/noaudit.jsonl" | Should -Be $false
    }
}

Context 'Mocked AD lifecycle behavior' {
    BeforeEach {
        $c=Read-LabConfig "$global:LabTestRepo/config/lab.example.json"
        $global:LabTestState=@{
            Config=$c; Domain='corp.example.test'; Nested=$false; FailGroups=$false; FailLookup=$false
            User=[pscustomobject]@{
                SamAccountName='alice.chen'; EmployeeID='LAB001'; adminCount=0; PrimaryGroupID=513
                SID='S-1-5-21-100-200-300-1100'; DistinguishedName="CN=alice.chen,$($c.UsersOU)"
                ObjectGUID=[guid]'00000000-0000-0000-0000-000000000001'
                MemberOf=@("CN=LAB-IT,$($c.GroupsOU)"); Enabled=$false
            }
        }
        @('SamAccountName,GivenName,Surname,EmployeeID,Department,Groups','alice.chen,Alice,Chen,LAB001,IT,LAB-Employees;LAB-IT') | Set-Content "$TestDrive/input.csv"
        Remove-Item "$TestDrive/audit.jsonl" -ErrorAction SilentlyContinue
        Mock Import-Module {} -ModuleName LabLifecycle
        Mock Get-ADDomain { [pscustomobject]@{DNSRoot=$global:LabTestState.Domain; DistinguishedName=$global:LabTestState.Config.BaseDN; DomainSID='S-1-5-21-100-200-300'} } -ModuleName LabLifecycle
        Mock Get-ADOrganizationalUnit {} -ModuleName LabLifecycle
        Mock Get-ADGroup { [pscustomobject]@{DistinguishedName="CN=$Identity,$($global:LabTestState.Config.GroupsOU)"; adminCount=0; GroupCategory='Security'} } -ModuleName LabLifecycle
        Mock Get-ADPrincipalGroupMembership { if($global:LabTestState.Nested){[pscustomobject]@{Name='Domain Admins'}} } -ModuleName LabLifecycle
        Mock Get-ADUser { if($global:LabTestState.FailLookup){throw 'LDAP unavailable'}; if($global:LabTestState.User){$global:LabTestState.User} } -ModuleName LabLifecycle
        Mock Get-ADGroupMember {} -ModuleName LabLifecycle
        Mock New-ADUser {
            $global:LabTestState.User=[pscustomobject]@{SamAccountName=$SamAccountName; ObjectGUID=[guid]'00000000-0000-0000-0000-000000000002'}
        } -ModuleName LabLifecycle
        Mock Set-ADUser {} -ModuleName LabLifecycle
        Mock Add-ADGroupMember { if($global:LabTestState.FailGroups){throw 'Group write failed'} } -ModuleName LabLifecycle
        Mock Disable-ADAccount {} -ModuleName LabLifecycle
        Mock Set-ADAccountPassword {} -ModuleName LabLifecycle
        Mock Remove-ADGroupMember {} -ModuleName LabLifecycle
        Mock Move-ADObject {} -ModuleName LabLifecycle
        $script:invoke=@{ConfigPath="$global:LabTestRepo/config/lab.example.json";CsvPath="$TestDrive/input.csv";AuditPath="$TestDrive/audit.jsonl";Apply=$true;Confirm=$false}
    }
    It 'does not mutate AD with WhatIf even when Apply is specified' {
        Invoke-LabLifecycle @script:invoke -Action Offboard -WhatIf
        Assert-MockCalled Disable-ADAccount -Times 0 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Set-ADAccountPassword -Times 0 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Remove-ADGroupMember -Times 0 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Move-ADObject -Times 0 -ModuleName LabLifecycle -Scope It
        Test-Path "$TestDrive/audit.jsonl" | Should -Be $false
    }
    It 'rejects connection to a different domain' {
        $global:LabTestState.Domain='production.example.com'
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
        Assert-MockCalled Disable-ADAccount -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'does not interpret a lookup error as absence' {
        $global:LabTestState.FailLookup=$true
        { Invoke-LabLifecycle @script:invoke -Action Onboard } | Should -Throw
        Assert-MockCalled New-ADUser -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'rejects employee identity mismatches' {
        $global:LabTestState.User.EmployeeID='LAB999'
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
        Assert-MockCalled Disable-ADAccount -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'rejects users outside lifecycle OUs' {
        $global:LabTestState.User.DistinguishedName='CN=alice.chen,CN=Users,DC=corp,DC=example,DC=test'
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
    }
    It 'rejects adminCount protected users' {
        $global:LabTestState.User.adminCount=1
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
    }
    It 'rejects privileged primary group membership' {
        $global:LabTestState.User.PrimaryGroupID=512
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
    }
    It 'rejects built-in RIDs despite a renamed account' {
        $global:LabTestState.User.SID='S-1-5-21-100-200-300-500'
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
    }
    It 'rejects unmanaged group memberships' {
        $global:LabTestState.User.MemberOf=@('CN=Domain Admins,CN=Users,DC=corp,DC=example,DC=test')
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
    }
    It 'rejects indirect privileges through nested lab groups' {
        $global:LabTestState.Nested=$true
        { Invoke-LabLifecycle @script:invoke -Action Onboard } | Should -Throw
        Assert-MockCalled Set-ADUser -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'refuses automatic rehire of offboarded accounts' {
        $global:LabTestState.User.DistinguishedName="CN=alice.chen,$($global:LabTestState.Config.DisabledOU)"
        { Invoke-LabLifecycle @script:invoke -Action Onboard } | Should -Throw
    }
    It 'preflights the entire batch before disabling the first user' {
        Add-Content "$TestDrive/input.csv" 'missing.user,Missing,User,LAB002,IT,LAB-Employees'
        Mock Get-ADUser { if($Filter -match 'missing.user|LAB002'){return}; $global:LabTestState.User } -ModuleName LabLifecycle
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
        Assert-MockCalled Disable-ADAccount -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'creates new users disabled with a SecureString password' {
        $global:LabTestState.User=$null
        Invoke-LabLifecycle @script:invoke -Action Onboard
        Assert-MockCalled New-ADUser -Times 1 -ModuleName LabLifecycle -Scope It -ParameterFilter { $Enabled -eq $false -and $AccountPassword -is [securestring] }
        Assert-MockCalled Add-ADGroupMember -Times 2 -ModuleName LabLifecycle -Scope It
    }
    It 'updates existing lab users without resetting passwords or creating duplicates' {
        Invoke-LabLifecycle @script:invoke -Action Onboard
        Assert-MockCalled New-ADUser -Times 0 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Set-ADUser -Times 1 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Set-ADAccountPassword -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'skips already assigned group memberships' {
        Mock Get-ADGroupMember { $global:LabTestState.User } -ModuleName LabLifecycle
        Invoke-LabLifecycle @script:invoke -Action Onboard
        Assert-MockCalled Add-ADGroupMember -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'disables, resets password, removes lab groups, and moves without deleting' {
        Invoke-LabLifecycle @script:invoke -Action Offboard
        Assert-MockCalled Disable-ADAccount -Times 1 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Set-ADAccountPassword -Times 1 -ModuleName LabLifecycle -Scope It -ParameterFilter { $Reset -and $NewPassword -is [securestring] }
        Assert-MockCalled Remove-ADGroupMember -Times 1 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Move-ADObject -Times 1 -ModuleName LabLifecycle -Scope It
        $events=@(Get-Content "$TestDrive/audit.jsonl" | ConvertFrom-Json)
        $events[-2].Status | Should -Be 'Succeeded'
        $events[-1].Status | Should -Be 'Completed'
        (Get-Content "$TestDrive/audit.jsonl" -Raw) | Should -Not -Match 'Password|GivenName|Surname'
    }
    It 'does not move an already quarantined account a second time' {
        $global:LabTestState.User.DistinguishedName="CN=alice.chen,$($global:LabTestState.Config.DisabledOU)"
        Invoke-LabLifecycle @script:invoke -Action Offboard
        Assert-MockCalled Move-ADObject -Times 0 -ModuleName LabLifecycle -Scope It
    }
    It 'orders offboarding so disabling precedes password reset, group removal and moving' {
        $global:LabTestState.Steps=New-Object System.Collections.Generic.List[string]
        Mock Disable-ADAccount { $global:LabTestState.Steps.Add('Disable') } -ModuleName LabLifecycle
        Mock Set-ADAccountPassword { $global:LabTestState.Steps.Add('Reset') } -ModuleName LabLifecycle
        Mock Remove-ADGroupMember { $global:LabTestState.Steps.Add('Groups') } -ModuleName LabLifecycle
        Mock Move-ADObject { $global:LabTestState.Steps.Add('Move') } -ModuleName LabLifecycle
        Invoke-LabLifecycle @script:invoke -Action Offboard
        ($global:LabTestState.Steps -join ',') | Should -Be 'Disable,Reset,Groups,Move'
    }
    It 'stops after a reset failure and reports partial completion after disabling' {
        Mock Set-ADAccountPassword { throw 'Reset refused' } -ModuleName LabLifecycle
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
        Assert-MockCalled Disable-ADAccount -Times 1 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Remove-ADGroupMember -Times 0 -ModuleName LabLifecycle -Scope It
        Assert-MockCalled Move-ADObject -Times 0 -ModuleName LabLifecycle -Scope It
        $events=@(Get-Content "$TestDrive/audit.jsonl" | ConvertFrom-Json)
        $events[-1].Status | Should -Be 'Failed'
        $events[-1].Step | Should -Be 'ResetPassword'
    }
    It 'fails visibly and records the failed operation without claiming success' {
        $global:LabTestState.FailGroups=$true
        { Invoke-LabLifecycle @script:invoke -Action Onboard } | Should -Throw
        $events=@(Get-Content "$TestDrive/audit.jsonl" | ConvertFrom-Json)
        $events[-1].Status | Should -Be 'Failed'
        $events[-1].Step | Should -Be 'Groups'
    }
    It 'does not mutate if the audit destination cannot be opened' {
        $script:invoke.AuditPath=$TestDrive
        { Invoke-LabLifecycle @script:invoke -Action Offboard } | Should -Throw
        Assert-MockCalled Disable-ADAccount -Times 0 -ModuleName LabLifecycle -Scope It
    }
}

AfterAll {
    Remove-Module LabLifecycle -Force -ErrorAction SilentlyContinue
    Remove-Variable LabTestState,LabTestRepo -Scope Global -ErrorAction SilentlyContinue
}

}


