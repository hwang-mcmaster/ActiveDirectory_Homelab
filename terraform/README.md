# Small Terraform Hyper-V component

This is an intentionally small **creation-job wrapper**, using the built-in `terraform_data` resource and local PowerShell. It creates real powered-off Hyper-V VM shells when explicitly enabled, but it is not a Hyper-V provider and does not implement ongoing VM drift detection, import, update or teardown. Windows installation and AD setup remain guest-side steps.

Requirements: Terraform >=1.5,<2 (locally validated with 1.9.8), Windows PowerShell 5.1, enabled Hyper-V module, elevated host/Hyper-V operator privileges, an existing dedicated Private switch, sufficient local disk/RAM, and valid ISO paths. The script validates VM names and sizes again at runtime. No third-party provider download or Hyper-V remoting credentials are required.

From this directory:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: correct drive/ISO paths, leave provision=false initially.
terraform init
terraform fmt -check
terraform validate
terraform plan
```

With `provision=false` (default), no jobs/VMs are created. After preparing the host and reviewing the example settings:

```powershell
terraform plan -var='provision=true' -out=lab.tfplan
terraform show lab.tfplan
# Explicit apply in an elevated host session; this executes local PowerShell:
terraform apply lab.tfplan
Get-VM LAB-DC01,LAB-CL01 | Select-Object Name,State,Generation,ProcessorCount,MemoryStartup
```

Use `provision=true` in your private tfvars for subsequent plans after this opt-in; otherwise a later plan proposes removing creation-job records from state. Keep state private and backed up. `creation_jobs` output lists job keys, not guest readiness. Starting VMs, installing Windows and configuring AD are documented in [setup](../docs/setup.md).

Important lifecycle behavior:

- The VM specification and storage/switch values trigger job replacement when changed. A rerun refuses an existing VM rather than applying changes to it. Inspect the planned replacement and perform reviewed manual changes instead of assuming Terraform will resize or rebuild it.
- Terraform does not query Hyper-V on refresh. A deleted or changed VM is not detected. Verify with Get-VM/Get-VMHardDiskDrive/Get-VMSnapshot and guest health checks.
- Partial creation may leave a VM or directory behind. Inspect it and retain important disks; never erase a directory merely to make a retry succeed. The script refuses adoption even if the name/spec appears to match.
- `terraform destroy`, removing a map entry, or setting `provision=false` removes job state **only**. It never deletes VMs, disks or the switch. A subsequent apply can then fail because the VM still exists.
- Lost state cannot be repaired by blindly importing VMs into terraform_data. Restore backed-up job state, or document that the VM is now manually managed. There is no native resource import/drift management here.
- Manual teardown: verify the exact lab VM name and disk paths, confirm backups/retention, shut down the lab guests, then remove VM registrations/disks/switch separately in Hyper-V Manager after explicit review. No automatic destructive teardown script is included.

Parameters reach PowerShell via environment variables containing JSON, not interpolated shell fragments. Do not put credentials in tfvars or command lines. CI runs a default no-VM plan and never applies this configuration.
