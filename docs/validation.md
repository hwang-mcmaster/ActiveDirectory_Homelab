# Validation record and live acceptance

## Implementation validation — 2026-11-09

| Check | Observed result |
| --- | --- |
| Destination inspection | Requested Sysadmin folder existed and was empty; no Git repository or inherited AGENTS.md found along its directory ancestry |
| PowerShell parsing | All repository .ps1/.psm1/.psd1 files parsed successfully |
| Config/CSV examples | Both lifecycle examples validated |
| Pester 5.7.1 / Windows PowerShell 5.1 | 45 passed, 0 failed |
| Pester 5.7.1 / PowerShell 7 | 45 passed, 0 failed |
| Terraform 1.9.8 | fmt check, init and validate passed |
| Default Terraform plan | Zero infrastructure resources; empty creation_jobs output proposed |
| Explicit opt-in example plan | 2 creation jobs proposed, 0 changes, 0 destroys; not applied |
| Host/guest mutations | None: no Windows features, switches, VMs, domain, GPO or accounts configured |
| GitHub Actions | Workflow supplied; remote execution not verified |

Tests cover CSV/config rejection, offline and online WhatIf behavior, AD domain/identity/OU/privilege boundaries, nested groups, batch preflight, disabled-first creation, additive repeat onboarding, repeat quarantine, offboarding ordering, partial failure and audit failure handling. Infrastructure tests cover offline plans and invalid VM parameters, not real Hyper-V calls. These are mocked/unit tests, not evidence of a running domain or end-to-end guest behavior.

Terraform and Pester were downloaded into the implementation task's temporary tools folder for validation. Terraform's archive SHA256 was checked against HashiCorp's published sums. No machine-wide tooling installation was performed. Install the prerequisites separately before using this repository on another machine.

## Host inventory at inspection

- Windows 11 Pro, version 10.0.26200; approximately 31.8 GiB physical RAM and 24 logical processors.
- HypervisorPresent reported true. Hyper-V PowerShell and ActiveDirectory modules were not available in the inspected Windows PowerShell session.
- FirmwareVirtualizationEnabled reported false while a hypervisor was present; this is inconclusive in this environment and is not treated as proof virtualization is disabled. Verify through local firmware/Windows feature checks.
- Session was not an administrator. Reading the Windows Hyper-V optional-feature state required elevation and was not completed; feature enablement is unverified.
- Free space at inspection: C: approximately 215.5 GiB, D: 605.1 GiB, E: 462.1 GiB. Capacity is a point-in-time observation, not a reservation.
- Git and Windows PowerShell/PowerShell 7 were available. Terraform was not on PATH before temporary validation tooling was obtained. Only the legacy Pester 3.4 module was initially available.

No ISO availability, Windows licenses, existing VM inventory, guest OS, AD/DNS service, effective GPO, actual ACL delegation, backup or restore has been verified. The host appears to have enough RAM/disk for the suggested two-guest lab, subject to current host workload and the remaining feature/firmware checks.

## Live acceptance checklist — all pending

- [ ] Confirm Hyper-V feature, management module, firmware readiness and administrator/operator access.
- [ ] Prepare a dedicated Private switch, legitimate ISOs, storage and VM shells.
- [ ] Install Windows guests and record actual VM configuration/state.
- [ ] Assign isolated static IPs, correct DNS and time; promote DC01 and reboot.
- [ ] Verify AD domain identity, DNS SRV records, NTDS/DNS/Netlogon and dcdiag results.
- [ ] Initialize protected OUs, flat security groups and workstation GPO.
- [ ] Join CL01; verify secure channel and effective 900-second lock policy.
- [ ] Apply sample onboarding; verify disabled accounts and expected memberships.
- [ ] Securely activate one user; verify first logon/password change and a rerun without duplicates.
- [ ] Test delegated lifecycle rights and confirm writes outside the lab fail.
- [ ] Apply offboarding; verify disablement, group removal, retained identity and Disabled OU.
- [ ] Review active-session/ticket limitations and complete session cleanup separately.
- [ ] Review real audit records and a controlled partial-failure/retry drill.
- [ ] Complete a real AD-aware backup and isolated recovery drill if claiming recovery capability.
- [ ] Review/redact evidence and confirm remote CI results after publication.

Record actual outcomes, dates and sanitized evidence next to each completed item. Do not replace pending checks with assumed successes.

