# Lifecycle operations and recovery

Run directory operations on DC01 or a trusted domain-joined management server with the ActiveDirectory module in Windows PowerShell 5.1. Never run two lifecycle jobs against the same accounts concurrently. The sample data is synthetic; copy it to a private ignored CSV before adapting it.

## Onboarding

Required fields: `SamAccountName,GivenName,Surname,EmployeeID,Department,Groups`. Account names are 2–20 ASCII letters/digits/dots/hyphens starting with a letter; employee IDs follow `LAB` plus 3–8 digits. Departments and groups must match the configuration. Separate groups with semicolons. All rows are validated before AD access; apply preflights the whole batch before the first write.

```powershell
Copy-Item ./data/onboarding.example.csv ./data/onboarding.csv
# Offline input validation and intent preview:
./scripts/Invoke-UserLifecycle.ps1 -Action Onboard -CsvPath ./data/onboarding.csv -ConfigPath ./config/lab.json
# Online domain, identity, OU and group preflight; no writes:
./scripts/Invoke-UserLifecycle.ps1 -Action Onboard -CsvPath ./data/onboarding.csv -ConfigPath ./config/lab.json -Apply -WhatIf
# Apply, with per-account confirmation:
./scripts/Invoke-UserLifecycle.ps1 -Action Onboard -CsvPath ./data/onboarding.csv -ConfigPath ./config/lab.json -Apply
Get-ADUser alice.chen -Properties Enabled,EmployeeID,Department,MemberOf -Server DC01.corp.example.test
```

New accounts are created **disabled**, with independently generated random passwords that are never returned or logged. Set a unique temporary password in a secure interactive session, deliver it using your approved secure channel, then activate the account after reviewing group membership:

```powershell
$temporaryPassword = Read-Host 'Unique temporary password for alice.chen' -AsSecureString
Set-ADAccountPassword -Identity alice.chen -Server DC01.corp.example.test -Reset -NewPassword $temporaryPassword
Set-ADUser -Identity alice.chen -Server DC01.corp.example.test -ChangePasswordAtLogon $true
Enable-ADAccount -Identity alice.chen -Server DC01.corp.example.test
Remove-Variable temporaryPassword
```

Do not enable an account after a failed lifecycle run until the failure has been reviewed. Repeating onboarding for an owned existing user updates name/department fields and adds missing groups; it does not reset a password, enable the user, or remove existing groups. Department changes need a separate access review. An account in Disabled requires a deliberate manual rehire process with fresh approval, not an onboarding rerun.

## Offboarding

Required CSV fields: `SamAccountName,EmployeeID`. The identity must already exist, have the matching employee ID, be within Users or Disabled, have ordinary Domain Users as its primary group and have only approved lab group memberships. Protected/built-in accounts, adminCount accounts, and indirect privileges through nested lab groups are refused.

```powershell
./scripts/Invoke-UserLifecycle.ps1 -Action Offboard -CsvPath ./data/offboarding.example.csv -ConfigPath ./config/lab.json
./scripts/Invoke-UserLifecycle.ps1 -Action Offboard -CsvPath ./data/offboarding.example.csv -ConfigPath ./config/lab.json -Apply -WhatIf
./scripts/Invoke-UserLifecycle.ps1 -Action Offboard -CsvPath ./data/offboarding.example.csv -ConfigPath ./config/lab.json -Apply
Get-ADUser alice.chen -Properties Enabled,MemberOf,EmployeeID -Server DC01.corp.example.test
```

Order: disable account, record that milestone, reset its password to an unknown random value, remove its approved direct group memberships, and move it to Disabled. No user or data deletion occurs. Rerunning offboarding is safe for a retained owned account: disable/reset may repeat, removed memberships stay absent, and an already-quarantined account is not moved again.

Disabling and resetting a password do not immediately terminate existing sessions, invalidate all issued tickets, disable cached offline logon, remove local group assignments, or revoke cloud access. For a full offboarding drill: identify active sessions on relevant guests, sign the user out, disconnect SMB/RDP sessions, consider ticket lifetime, inspect scheduled tasks/services, revoke any separate cloud/VPN access, and preserve required data. Those actions require separate operator review and are not automated here.

## Audit and failure handling

`logs/lifecycle.jsonl` contains UTC timestamp, run ID, actor name, account, action, status and step. Each line is a JSON object; no CSV payload, password, secure string or raw exception text is logged. Account/actor names still identify people, so logs are ignored by Git and require private storage. The destination must be writable before account mutations begin. Run only one writer per log destination; use separate `-AuditPath` values for concurrent unrelated jobs.

```powershell
Get-Content ./logs/lifecycle.jsonl | ForEach-Object { $_ | ConvertFrom-Json } | Format-Table TimestampUtc,RunId,Account,Action,Status,Step
```

Preflight failures terminate before account changes and may occur before an audit file exists. Console errors are part of the operator record. Apply with `-WhatIf` performs reads only and writes no audit file. Declined confirmation is recorded as Skipped; a completed batch can contain skipped accounts. A terminating mutation error records Failed with the current step and stops the remaining batch. Any earlier accounts/steps may already have succeeded. Audit storage failure after a mutation also causes termination and may prevent the failure record; reconcile actual AD state rather than assuming rollback.

Recovery procedure:

1. Stop automation. Note the run ID, failed account, failed step and last successful events.
2. Inspect the affected user by employee ID and GUID, its Enabled flag, OU and memberships. Verify changes directly on the configured DC.
3. Keep newly created users disabled. Fix permissions, connectivity, audit storage or policy failure. Do not broaden the allowlist to bypass a privileged-account refusal.
4. Run an online WhatIf, then retry only the affected/remaining rows. A newly created disabled account can finish onboarding on rerun; existing passwords are retained.
5. For a failed offboarding after Disable, keep the account disabled and complete password reset, group removal and quarantine. No automated re-enable or rollback is provided.
6. A mistaken offboarding needs separate approval and manual password reset, OU/group restoration from reviewed pre-change evidence, and explicit enabling. Retention/deletion is a separate workflow.

There is no cross-account transaction, distributed lock, or protection against an administrator concurrently moving or privileging an account after preflight. Use an exclusive maintenance window in this lab. The tool is intentionally restricted, not a production IAM platform.

## Health, backup and recovery practice

Run `./scripts/Test-LabHealth.ps1 -ConfigPath ./config/lab.json`, review `dcdiag /v`, DNS event logs, client secure channel and `gpresult`. With multiple DCs in a future extension, additionally use `repadmin /replsummary`; a single-DC success cannot demonstrate replication resilience.

For a backup exercise, install Windows Server Backup inside the server guest after review (`Install-WindowsFeature Windows-Server-Backup`), attach a dedicated backup disk, and use a volume that does not contain the OS/AD database. After confirming the correct target, run an elevated guest `wbadmin start systemstatebackup -backupTarget:E: -quiet` and inspect `wbadmin get versions -backupTarget:E:`. Replace E: with the actual dedicated backup volume; the example command is not a supplied backup device. Protect backup data and DSRM credentials separately from the VM. Perform a documented restore drill only in an isolated disposable copy using Microsoft's AD DS recovery guidance; do not reconnect a restored copy to an active domain without a recovery plan.

Hyper-V checkpoints are short-lived lab convenience points, not a substitute for AD-aware backups. Do not use automatic DC checkpoint rollback as the offboarding recovery method. Record measured restore outcomes and evidence only after an actual test.
