variable "provision" {
  type        = bool
  default     = false
  description = "Explicit opt-in to execute Hyper-V creation on this Windows host."
}

variable "vm_root" {
  type        = string
  default     = "D:\\SysadminLab"
  description = "Dedicated local disk directory with sufficient free space."
}

variable "switch_name" {
  type    = string
  default = "SysadminLab-Private"
}

variable "vms" {
  type = map(object({
    memory_gib = number
    cpu_count  = number
    disk_gib   = number
    iso        = string
  }))
  default = {}
  validation {
    condition = alltrue([for name, vm in var.vms :
      contains(["LAB-DC01", "LAB-CL01", "LAB-FS01"], name) &&
      vm.memory_gib >= 2 && vm.memory_gib <= 16 && floor(vm.memory_gib) == vm.memory_gib &&
      vm.cpu_count >= 1 && vm.cpu_count <= 8 && floor(vm.cpu_count) == vm.cpu_count &&
      vm.disk_gib >= 64 && vm.disk_gib <= 256 && floor(vm.disk_gib) == vm.disk_gib
    ])
    error_message = "Use approved LAB VM names, integer RAM 2..16 GiB, CPUs 1..8 and disk 64..256 GiB."
  }
}
