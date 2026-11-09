# Step-by-step setup

Run commands from the repository root unless otherwise stated. Host commands and guest commands are explicitly separated. No infrastructure commands in this guide have been executed as part of repository implementation.

## 1. Inspect and prepare the physical host

Open Windows PowerShell 5.1 and run `./scripts/Test-HostReadiness.ps1`. Verify Windows Pro/Enterprise, firmware virtualization, available RAM, disk capacity and Windows updates. Some feature/hardware checks require elevation. Do not infer that Hyper-V is enabled solely from the Windows edition.

When ready, in an **administrator host** session:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
# Only if needed; this changes Windows and requires a restart:
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
```

Save work and restart the host manually if required. Verify `Get-Module -ListAvailable Hyper-V` and `Get-VMHost`. A firmware change may be needed if virtualization is disabled. Hyper-V commands require an administrator or delegated Hyper-V operator; an unelevated discovery failure is not proof the feature is absent.

Create the isolated switch once, after verifying no conflicting switch exists:

```powershell
Get-VMSwitch
New-VMSwitch -Name SysadminLab-Private -SwitchType Private
Get-VMSwitch -Name SysadminLab-Private | Format-List Name,SwitchType
```

Do not rerun New-VMSwitch if it already exists. No NAT, external switch or DHCP server is created by this project.

## 2. Provision powered-off guests

Obtain legitimate Windows Server and Windows 11 Pro/Enterprise ISOs. Create a dedicated storage root on a drive with capacity; replace the example `D:` paths if absent. Choose **either** direct PowerShell or [Terraform](../terraform/README.md) for a given VM, not both.

```powershell
# Preview, then explicitly apply in an elevated host session:
./scripts/New-LabVM.ps1 -Name LAB-DC01 -Root 'D:\SysadminLab' -IsoPath 'D:\ISO\WindowsServer.iso'
./scripts/New-LabVM.ps1 -Name LAB-DC01 -Root 'D:\SysadminLab' -IsoPath 'D:\ISO\WindowsServer.iso' -Apply
./scripts/New-LabVM.ps1 -Name LAB-CL01 -Root 'D:\SysadminLab' -IsoPath 'D:\ISO\Windows11.iso' -DiskGiB 80 -Apply
Get-VM LAB-DC01,LAB-CL01 | Select-Object Name,State,Generation,MemoryStartup,ProcessorCount
Start-VM LAB-DC01
Start-VM LAB-CL01
vmconnect.exe localhost LAB-DC01
```

VM creation is Gen 2 with Secure Boot, an installer DVD, and a blank dynamic VHDX. CL01 additionally gets a local key protector/vTPM. Guests remain powered off until Start-VM. A partial failure is retained for inspection; no existing VM/disk is adopted or deleted. Do not rerun blindly after an error.

Install the guest operating systems through VMConnect, choosing Windows Server Desktop Experience on DC01 and a domain-capable client edition on CL01. Windows 11 installation/OOBE requirements vary by release and licensing; complete the supported organization setup for your media. If your image requires internet, use a separate staging network before configuring the isolated lab and before promoting the DC. This repository does not bypass setup or licensing requirements. Detach installation ISOs after installation and set the disk first in firmware boot order if necessary.

## 3. Transfer repository files into the guests

Use a sanitized copy without `.git`, logs, real CSVs, Terraform state or private files. On a Hyper-V host, PowerShell Direct works independently of the private guest network after Windows is running:

```powershell
$cred = Get-Credential # DC01 guest local administrator; never store in the repo
$session = New-PSSession -VMName LAB-DC01 -Credential $cred
# Use an existing sanitized source folder and an absolute guest destination.
Copy-Item -Path 'C:\LabTransfer\Sysadmin' -Destination 'C:\Lab' -Recurse -ToSession $session
Remove-PSSession $session
```

`C:\Lab` must exist in the guest before transfer (create it via VMConnect or Invoke-Command). Continue from `C:\Lab\Sysadmin` in the guest. Transfer the same folder to CL01 if desired.

## 4. Configure DC01 inside the server guest

In **administrator PowerShell inside LAB-DC01**, rename the guest:

```powershell
Rename-Computer -NewName DC01 -Restart
```

After reboot, identify the actual adapter name. Do not assume it is Ethernet. Ensure no conflicting IPv4 address exists before assigning:

```powershell
Get-NetAdapter
Get-NetIPConfiguration
# Replace Ethernet with the adapter you inspected:
New-NetIPAddress -InterfaceAlias Ethernet -IPAddress 10.50.0.10 -PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 10.50.0.10
```

No gateway is required. Remove stale staging-network routes/DNS configuration manually after review. Set the clock correctly; domain authentication depends on time synchronization.

```powershell
Copy-Item ./config/lab.example.json ./config/lab.json
./scripts/Install-LabForest.ps1 -ConfigPath ./config/lab.json
./scripts/Install-LabForest.ps1 -ConfigPath ./config/lab.json -Apply
```

The apply script accepts only a standalone Windows Server named DC01, installs AD DS/DNS, prompts for a DSRM recovery password, and requests forest creation without automatically restarting. It refuses the Windows client host. Store recovery credentials securely outside the repository. After successful promotion, restart DC01 manually. Sign in as `CORP\Administrator` using the server administrator password, then verify:

```powershell
Get-ADDomain
Get-ADDomainController -Filter *
Get-Service NTDS,DNS,Netlogon
Resolve-DnsName _ldap._tcp.dc._msdcs.corp.example.test -Type SRV -Server 10.50.0.10
dcdiag /test:DNS /v
```

A parent DNS delegation warning for this isolated `.test` forest can be expected; review the actual promotion results. Do not proceed on unrelated DNS or AD errors. A single-DC lab demonstrates no replication redundancy.

## 5. Create the lab OUs, groups and GPO

Inside DC01 as a domain administrator for this initial setup:

```powershell
./scripts/Initialize-LabDirectory.ps1 -ConfigPath ./config/lab.json
./scripts/Initialize-LabDirectory.ps1 -ConfigPath ./config/lab.json -Apply -WhatIf
./scripts/Initialize-LabDirectory.ps1 -ConfigPath ./config/lab.json -Apply
Get-ADOrganizationalUnit -Filter * -SearchBase 'OU=Lab,DC=corp,DC=example,DC=test'
Get-ADGroup -Filter 'Name -like "LAB-*"'
Get-GPO -Name LAB-Workstation-Lock
```

The initializer is additive and can be rerun. It updates its named GPO setting and links it to Workstations; review any existing same-name GPO before applying in a reused lab. It does not change the Default Domain Policy, password policy, or production security baselines.

## 6. Join CL01 to the domain

Inside the Windows client guest, rename to CL01 and restart, assign `10.50.0.20/24`, no gateway, and DNS `10.50.0.10` using the adapter-inspection steps above. Then:

```powershell
Resolve-DnsName DC01.corp.example.test -Server 10.50.0.10
Add-Computer -DomainName corp.example.test -OUPath 'OU=Workstations,OU=Lab,DC=corp,DC=example,DC=test' -Credential (Get-Credential 'CORP\Administrator') -Restart
```

After reboot sign in with a domain account. In an elevated client session:

```powershell
Test-ComputerSecureChannel -Verbose
gpupdate /force
gpresult /r /scope computer
New-Item -ItemType Directory -Path C:\LabEvidence -Force
gpresult /h C:\LabEvidence\gpresult.html
Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name InactivityTimeoutSecs
```

Expect `900` after policy application. Save sanitized evidence only after verification. For optional FS01, repeat with guest name FS01 and `10.50.0.30`; use a dedicated member-server OU and baseline if extending the lab.

## 7. Operate and verify

Follow [operations](operations.md) to onboard sample users, securely activate one, test a domain sign-in, and offboard it. Run `./scripts/Test-LabHealth.ps1 -ConfigPath ./config/lab.json` on DC01. Health checks fail with a nonzero error on failed probes, but do not prove client sign-in, effective GPO application, backups or recovery. Complete the [acceptance checklist](validation.md).
