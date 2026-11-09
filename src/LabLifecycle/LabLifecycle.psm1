Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-LabConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $c = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($key in @('DomainName','NetbiosName','Server','BaseDN','LabOU','UsersOU','DisabledOU','GroupsOU','ComputersOU','AllowedGroups','Departments','ProtectedAccounts','MaxBatchSize')) {
        if (-not $c.PSObject.Properties[$key] -or -not $c.$key) { throw "Missing configuration: $key" }
    }
    if ($c.DomainName -notmatch '^[a-z0-9-]+(\.[a-z0-9-]+)+$') { throw 'Invalid domain name.' }
    if ($c.BaseDN -ine (($c.DomainName.Split('.') | ForEach-Object { "DC=$_" }) -join ',')) { throw 'BaseDN must match DomainName.' }
    if ($c.LabOU -ine "OU=Lab,$($c.BaseDN)") { throw 'LabOU must be OU=Lab under the configured domain.' }
    foreach ($key in @('UsersOU','DisabledOU','GroupsOU','ComputersOU')) {
        if ($c.$key -notmatch '^OU=[A-Za-z][A-Za-z0-9-]*,' -or -not $c.$key.EndsWith(",$($c.LabOU)",[StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe OU: $key" }
    }
    if (@($c.UsersOU,$c.DisabledOU,$c.GroupsOU,$c.ComputersOU | Select-Object -Unique).Count -ne 4) { throw 'OUs must be distinct.' }
    if ($c.Server -notmatch '^[a-zA-Z0-9.-]+$' -or -not $c.Server.EndsWith(".$($c.DomainName)",[StringComparison]::OrdinalIgnoreCase)) { throw 'Server must be an FQDN in the lab domain.' }
    if ([int]$c.MaxBatchSize -lt 1 -or [int]$c.MaxBatchSize -gt 100) { throw 'MaxBatchSize must be 1..100.' }
    foreach ($g in $c.AllowedGroups) { if ($g -notmatch '^LAB-[A-Za-z0-9-]+$') { throw 'Only LAB- prefixed groups are allowed.' } }
    return $c
}

function Read-LifecycleCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Config,
          [Parameter(Mandatory)][ValidateSet('Onboard','Offboard')][string]$Action)
    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -eq 0 -or $rows.Count -gt $Config.MaxBatchSize) { throw 'CSV is empty or exceeds MaxBatchSize.' }
    $required = @('SamAccountName','EmployeeID')
    if ($Action -eq 'Onboard') { $required += @('GivenName','Surname','Department','Groups') }
    foreach ($key in $required) { if ($key -notin $rows[0].PSObject.Properties.Name) { throw "Missing CSV column: $key" } }
    $names = @{}; $ids = @{}
    foreach ($r in $rows) {
        foreach ($key in $required) { if ([string]::IsNullOrWhiteSpace($r.$key)) { throw "Empty CSV value: $key" } }
        if ($r.SamAccountName -notmatch '^[a-z][a-z0-9.\-]{1,19}$') { throw 'Invalid SamAccountName.' }
        if ($r.EmployeeID -notmatch '^LAB[0-9]{3,8}$') { throw 'EmployeeID must be LAB followed by 3..8 digits.' }
        if ($r.SamAccountName -in (@('Administrator','Guest','krbtgt') + @($Config.ProtectedAccounts))) { throw 'Protected account.' }
        if ($names.ContainsKey($r.SamAccountName) -or $ids.ContainsKey($r.EmployeeID)) { throw 'Duplicate account or EmployeeID in CSV.' }
        $names[$r.SamAccountName] = $true; $ids[$r.EmployeeID] = $true
        if ($Action -eq 'Onboard') {
            foreach ($key in @('GivenName','Surname')) { if ($r.$key.Length -gt 64 -or $r.$key -match '[\x00-\x1F]') { throw "Invalid $key" } }
            if ($r.Department -notin $Config.Departments) { throw 'Department is not approved.' }
            foreach ($g in $r.Groups.Split(';')) { if ($g -notin $Config.AllowedGroups) { throw "Unapproved group: $g" } }
        }
    }
    return $rows
}

function Write-LabAudit {
    param([string]$Path,[string]$RunId,[string]$Account,[string]$Action,[string]$Status,[string]$Step)
    # Never log passwords, CSV rows, or raw exception messages.
    [ordered]@{ TimestampUtc=[DateTime]::UtcNow.ToString('o'); RunId=$RunId; Actor=[Environment]::UserName; Account=$Account; Action=$Action; Status=$Status; Step=$Step } |
        ConvertTo-Json -Compress | Add-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
}

function New-LabPassword {
    $bytes = New-Object byte[] 36
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    ConvertTo-SecureString (('Aa1!' + [Convert]::ToBase64String($bytes))) -AsPlainText -Force
}

function Assert-LabUser {
    param($User,$Row,$Config,[string]$DomainSid)
    if ($User.EmployeeID -cne $Row.EmployeeID) { throw 'EmployeeID ownership mismatch.' }
    $inUsers = $User.DistinguishedName.EndsWith(",$($Config.UsersOU)",[StringComparison]::OrdinalIgnoreCase)
    $inDisabled = $User.DistinguishedName.EndsWith(",$($Config.DisabledOU)",[StringComparison]::OrdinalIgnoreCase)
    if (-not ($inUsers -or $inDisabled)) { throw 'Account is outside lifecycle OUs.' }
    if ($User.AdminCount -eq 1 -or [int]$User.PrimaryGroupID -ne 513) { throw 'Privileged or nonstandard account refused.' }
    if ([string]$User.SID -notlike "$DomainSid-*" -or [int](([string]$User.SID).Split('-')[-1]) -lt 1000) { throw 'Built-in or foreign account refused.' }
}

function Invoke-LabLifecycle {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][string]$CsvPath,
          [Parameter(Mandatory)][ValidateSet('Onboard','Offboard')][string]$Action,
          [switch]$Apply,[string]$AuditPath = (Join-Path (Get-Location) 'logs/lifecycle.jsonl'))
    $c = Read-LabConfig $ConfigPath
    $rows = @(Read-LifecycleCsv -Path $CsvPath -Config $c -Action $Action)
    # Offline plans validate intent, not existence/permissions. No AD module required.
    if (-not $Apply) {
        foreach ($r in $rows) { [pscustomobject]@{Mode='OfflinePlan'; Action=$Action; Account=$r.SamAccountName; TargetOU=$(if($Action -eq 'Onboard'){$c.UsersOU}else{$c.DisabledOU})} }
        return
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    $ad = @{Server=$c.Server; ErrorAction='Stop'}
    $domain = Get-ADDomain @ad
    if ($domain.DNSRoot -ine $c.DomainName -or $domain.DistinguishedName -ine $c.BaseDN) { throw 'Connected domain does not match config.' }
    foreach ($ou in @($c.UsersOU,$c.DisabledOU,$c.GroupsOU)) { Get-ADOrganizationalUnit -Identity $ou @ad | Out-Null }
    $groups = @{}
    foreach ($g in $c.AllowedGroups) {
        $group = Get-ADGroup -Identity $g -Properties adminCount @ad
        if (-not $group.DistinguishedName.EndsWith(",$($c.GroupsOU)",[StringComparison]::OrdinalIgnoreCase) -or $group.adminCount -eq 1 -or $group.GroupCategory -ne 'Security') { throw "Unsafe group: $g" }
        # Nested groups could grant privileges indirectly; require flat lab groups.
        if (@(Get-ADPrincipalGroupMembership -Identity $group @ad).Count -gt 0) { throw "Nested lab group refused: $g" }
        $groups[$g] = $group.DistinguishedName
    }
    # Preflight the whole batch before the first mutation. Query failures never mean 'absent'.
    $work = foreach ($r in $rows) {
        $users = @(Get-ADUser -Filter "SamAccountName -eq '$($r.SamAccountName)'" -Properties EmployeeID,adminCount,PrimaryGroupID,MemberOf @ad)
        $byId = @(Get-ADUser -Filter "EmployeeID -eq '$($r.EmployeeID)'" @ad)
        if ($users.Count -gt 1 -or @($byId | Where-Object { $_.SamAccountName -ine $r.SamAccountName }).Count -gt 0) { throw 'Ambiguous account ownership.' }
        $user = $null
        if ($users.Count -eq 1) {
            $user = $users[0]; Assert-LabUser $user $r $c ([string]$domain.DomainSID)
            if ($Action -eq 'Onboard' -and -not $user.DistinguishedName.EndsWith(",$($c.UsersOU)",[StringComparison]::OrdinalIgnoreCase)) { throw 'Offboarded account requires manual rehire review.' }
            foreach ($dn in @($user.MemberOf)) {
                if ($dn -notin $groups.Values) { throw 'Account has unmanaged memberships; review manually.' }
            }
        } elseif ($Action -eq 'Offboard') { throw "Account does not exist: $($r.SamAccountName)" }
        [pscustomobject]@{ Row=$r; User=$user }
    }
    if ($WhatIfPreference) {
        foreach ($item in $work) {
            $null = $PSCmdlet.ShouldProcess("$($c.Server)/$($item.Row.SamAccountName)","$Action lab account")
            [pscustomobject]@{Mode='OnlineWhatIf';Action=$Action;Account=$item.Row.SamAccountName;Status='NoChanges'}
        }
        return
    }
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($AuditPath))
    New-Item -ItemType Directory -Path $parent -Force -WhatIf:$false | Out-Null
    $runId = [guid]::NewGuid().ToString()
    Write-LabAudit $AuditPath $runId '-' $Action 'Started' 'PreflightComplete'
    foreach ($item in $work) {
        $r = $item.Row; $u = $item.User; $step = 'Approval'
        if (-not $PSCmdlet.ShouldProcess("$($c.Server)/$($r.SamAccountName)","$Action lab account")) {
            Write-LabAudit $AuditPath $runId $r.SamAccountName $Action 'Skipped' $step
            continue
        }
        try {
            Write-LabAudit $AuditPath $runId $r.SamAccountName $Action 'Started' 'Account'
            if ($Action -eq 'Onboard') {
                if (-not $u) {
                    $step = 'CreateDisabled'
                    New-ADUser -Name $r.SamAccountName -SamAccountName $r.SamAccountName -UserPrincipalName "$($r.SamAccountName)@$($c.DomainName)" -GivenName $r.GivenName -Surname $r.Surname -EmployeeID $r.EmployeeID -Department $r.Department -Path $c.UsersOU -Enabled $false -AccountPassword (New-LabPassword) @ad
                    $u = Get-ADUser -Identity $r.SamAccountName @ad
                    Write-LabAudit $AuditPath $runId $r.SamAccountName $Action 'StepComplete' $step
                }
                $step = 'Profile'
                Set-ADUser -Identity $u.ObjectGUID -GivenName $r.GivenName -Surname $r.Surname -Department $r.Department @ad
                $step = 'Groups'
                foreach ($g in $r.Groups.Split(';') | Select-Object -Unique) {
                    $members = @(Get-ADGroupMember -Identity $groups[$g] @ad)
                    if ($u.ObjectGUID -notin @($members | Select-Object -ExpandProperty ObjectGUID)) { Add-ADGroupMember -Identity $groups[$g] -Members $u.ObjectGUID @ad }
                }
                # Never enable automatically or expose a shared bootstrap password.
            } else {
                $step = 'Disable'; Disable-ADAccount -Identity $u.ObjectGUID @ad
                Write-LabAudit $AuditPath $runId $r.SamAccountName $Action 'StepComplete' $step
                $step = 'ResetPassword'; Set-ADAccountPassword -Identity $u.ObjectGUID -Reset -NewPassword (New-LabPassword) @ad
                $step = 'RemoveGroups'
                foreach ($dn in @($u.MemberOf)) { Remove-ADGroupMember -Identity $dn -Members $u.ObjectGUID -Confirm:$false @ad }
                $step = 'Move'
                if (-not $u.DistinguishedName.EndsWith(",$($c.DisabledOU)",[StringComparison]::OrdinalIgnoreCase)) { Move-ADObject -Identity $u.ObjectGUID -TargetPath $c.DisabledOU @ad }
            }
            Write-LabAudit $AuditPath $runId $r.SamAccountName $Action 'Succeeded' 'Complete'
            [pscustomobject]@{Mode='Applied'; Action=$Action; Account=$r.SamAccountName; Status='Succeeded'}
        } catch {
            Write-LabAudit $AuditPath $runId $r.SamAccountName $Action 'Failed' $step
            throw "Lifecycle stopped at $step for $($r.SamAccountName). Review AD and audit; earlier steps may have completed."
        }
    }
    Write-LabAudit $AuditPath $runId '-' $Action 'Completed' 'Batch'
}
Export-ModuleMember -Function Read-LabConfig,Read-LifecycleCsv,Invoke-LabLifecycle
