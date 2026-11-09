terraform {
  required_version = ">= 1.5.0, < 2.0.0"
}

# The built-in terraform_data resource tracks a creation job, not the VM itself.
# No destroy provisioner: terraform destroy NEVER removes VMs or disks.
resource "terraform_data" "vm" {
  for_each = var.provision ? var.vms : {}

  triggers_replace = [each.value, var.vm_root, var.switch_name]

  provisioner "local-exec" {
    interpreter = ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command"]
    command     = "& $env:LAB_VM_SCRIPT -FromTerraform"
    environment = {
      LAB_VM_SCRIPT = abspath("${path.module}/../scripts/New-LabVM.ps1")
      LAB_VM_SPEC = jsonencode({
        name        = each.key
        memory_gib  = each.value.memory_gib
        cpu_count   = each.value.cpu_count
        disk_gib    = each.value.disk_gib
        iso         = each.value.iso
        root        = var.vm_root
        switch_name = var.switch_name
      })
    }
  }
}

output "creation_jobs" {
  value       = keys(terraform_data.vm)
  description = "Creation jobs tracked by Terraform; not proof of VM or guest health."
}
