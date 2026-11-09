# Security boundaries

This repository is for an isolated, disposable lab. Initial forest/OU/GPO setup uses domain administrator privileges; day-to-day lifecycle operations should use a separate operator identity delegated only the required user/group rights in the lab OUs. Do not use Domain Admins for routine CSV jobs.

Delegate through AD Users and Computers (enable Advanced Features): create a separate lab operator account and security group, then use the Delegation of Control wizard on Users/Disabled to grant the required user create, profile/employeeID read/write, password reset, account restriction updates, and moves between these OUs. Moves require the appropriate delete-child/create-child rights on source/destination; do not grant broad object deletion rights at the domain root. Delegate group membership updates only on the approved group objects in Groups. Validate with a disposable user and confirm writes outside the lab fail. Exact ACLs depend on the chosen administrative model; delegation is a documented operator step, not implemented or claimed as verified by this repository.

Safeguards implemented in code:

- Default offline plans; `-Apply` for mutations and ShouldProcess confirmation/WhatIf support.
- Explicit DC and domain identity check, fixed OU=Lab boundary, distinct lifecycle OUs.
- Restricted CSV identifiers, duplicate employee/name rejection, bounded batch sizes, department/group allowlists.
- Whole-batch preflight, employee ownership checks, only lifecycle OUs, and no automatic rehire.
- Reject built-in RIDs, adminCount accounts, nonstandard primary groups, unmanaged memberships and nested lab groups.
- Disabled-first onboarding with per-account random passwords; no automatic enabling, shared passwords or password output.
- Disable-first retained offboarding, no account or VM deletion, no automatic rollback.
- Structured audit written before mutations, sanitized failure messages, ignored local data/state/evidence.
- VM creation only on an existing Private switch, strict lab VM names and no adoption/overwrite of existing files or VMs.

These checks are guardrails, not an authorization boundary against a malicious operator. Someone who can alter config/code or has domain rights can bypass them. Group safety assumes ordinary Domain Users membership and no manually assigned privileged ACLs/user rights to lab accounts or Domain Users. AD administrators must keep that invariant. Arbitrary delegation, ACL-based privileges, local administrator assignments, external systems and concurrent administrator changes are not comprehensively discovered.

Never commit passwords, DSRM credentials, employee data, private keys, VM images or real audit logs. `config/lab.json`, non-example CSVs, logs, reports/evidence, tfvars and Terraform state are ignored. `.gitignore` is not a secret scanner and does not remove previously tracked secrets. Review `git status`, staged diffs and any published artifacts; rotate a credential if exposed. Terraform configuration contains no passwords, but state and local paths still reveal environment information.

Do not run untrusted CSVs or Terraform from strangers with elevated privileges. Protect the local repository and audit directories with OS ACLs, keep a private audit archive with retention appropriate to the lab, and review before GitHub publication. No remote repository or credentials are configured by this project.
