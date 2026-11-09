# Enterprise IT Infrastructure & Active Directory Automation Lab

A GitHub portfolio project for Windows system administration: isolated Hyper-V guests, Windows Server AD DS/DNS, organizational units, a workstation GPO, and tested PowerShell employee lifecycle automation. A small Terraform component launches Hyper-V creation jobs using the same PowerShell script.

**Status:** repository implemented and locally validated; infrastructure is not deployed or verified. See [validation](docs/validation.md) for actual results and host limitations. No credentials, installers, VM disks, real employee data, or fabricated deployment screenshots are included.

## Start here

1. [Architecture and resource plan](docs/architecture.md)
2. [Step-by-step host, VM and domain setup](docs/setup.md)
3. [Onboarding, offboarding and recovery runbook](docs/operations.md)
4. [Terraform workflow and limitations](terraform/README.md)
5. [Validation and acceptance checklist](docs/validation.md)
6. [Security boundaries](docs/security.md) and [portfolio demo](docs/demo.md)

## Try it without a domain

From the repository root, in Windows PowerShell 5.1:

```powershell
# If local scripts are blocked, allow reviewed local scripts in this session only:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
./scripts/Test-HostReadiness.ps1
./scripts/Invoke-UserLifecycle.ps1 -Action Onboard -CsvPath ./data/onboarding.example.csv
./scripts/Invoke-UserLifecycle.ps1 -Action Offboard -CsvPath ./data/offboarding.example.csv
./scripts/New-LabVM.ps1 -Name LAB-DC01 -IsoPath 'D:\ISO\WindowsServer.iso'
./scripts/Install-LabForest.ps1
./scripts/Initialize-LabDirectory.ps1
```

These commands inspect or produce offline plans. They do not create VMs, a domain, or accounts. An offline plan validates input only; it cannot prove AD connectivity, permissions or object existence. Guest operations target Windows PowerShell 5.1 with Microsoft modules; the offline lifecycle module also supports PowerShell 7.

## Validate the code

```powershell
# One-time dependency installation; no administrator rights needed.
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
./scripts/Test-Repository.ps1

Push-Location terraform
terraform fmt -check
terraform init -backend=false
terraform validate
terraform plan -input=false
Pop-Location
```

The tests mock AD calls and do not need RSAT, a domain or Hyper-V. CI runs tests and a disabled-by-default Terraform plan; CI never applies infrastructure. Pester 3 bundled with Windows is too old for this suite. Use `Test-Repository.ps1 -SkipTests` for parsing/input checks only, without claiming tests passed.

The process-scoped execution policy ends when that PowerShell window closes. Organization-enforced policy may take precedence; follow it rather than changing machine-wide policy. Review downloaded scripts and their origin before unblocking any file.

## Repository map

| Path | Purpose |
| --- | --- |
| `src/LabLifecycle/` | CSV/config validation, scoped AD lifecycle module, JSONL audit |
| `scripts/` | Host readiness, VM creation, forest/OU/GPO setup, lifecycle CLI, health and test commands |
| `config/lab.example.json` | Lab domain, OU boundaries, group/department allowlists |
| `data/*.example.csv` | Synthetic employee inputs; semicolon-separated groups |
| `tests/` | Pester safety and mocked lifecycle behavior tests |
| `terraform/` | Opt-in Hyper-V creation jobs; no destructive teardown |
| `docs/` | Architecture, setup, operations, security, evidence and validation |
| `.github/workflows/` | Windows PowerShell tests and Terraform validation |

New users remain disabled until an operator securely sets an individual temporary password and enables them. Offboarding retains accounts and data; it does not terminate active sessions or revoke already-issued Kerberos tickets. Use the operations runbook for those separate steps.

## Technical references

The implementation uses Microsoft's [New-ADUser](https://learn.microsoft.com/powershell/module/activedirectory/new-aduser), [AD authorization group](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adaccountauthorizationgroup), [Hyper-V firmware](https://learn.microsoft.com/en-us/powershell/module/hyper-v/set-vmfirmware) interfaces and HashiCorp's built-in [terraform_data](https://developer.hashicorp.com/terraform/language/resources/terraform-data) / [local-exec](https://developer.hashicorp.com/terraform/language/provisioners) mechanism. Terraform tracks the creation job, not ongoing VM state; the limitations are explicit in its runbook.
