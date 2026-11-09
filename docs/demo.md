# Portfolio demonstration

Use this sequence after completing setup. Label any mock/test output clearly; never present it as deployed infrastructure.

1. Show the architecture, resource choices and Private switch isolation. Explain host vs guest responsibilities.
2. Show real Get-VM output for DC01/CL01, AD DNS SRV resolution and a domain-joined client secure-channel check.
3. Show Lab OUs, flat department groups, the workstation GPO link and actual client gpresult/registry value.
4. Preview a synthetic onboarding CSV offline, then online WhatIf. Apply, inspect disabled users and approved groups, securely activate one user, and demonstrate first domain sign-in/password change.
5. Rerun onboarding and show that it does not create duplicates or reset the existing password. Show a protected-account/unapproved-group rejection with no changes.
6. Preview/apply offboarding. Show disabled status, retained employee ID, removed lab groups and quarantine OU. Explain existing sessions/ticket limitations.
7. Show JSONL events grouped by run ID, with no passwords or full CSV payloads. Explain failure/partial completion recovery.
8. Run Pester and Terraform validation. Explain why terraform_data is limited to creation and why no automated deletion is provided.
9. Record an actual backup/restore drill if performed. State whether it is planned or measured.

Keep evidence under the ignored `evidence/` directory until reviewed. Suggested filenames: `host-vms.png`, `ad-ous.png`, `client-gpresult.html`, `lifecycle-sanitized.jsonl`, `test-results.txt`, and `recovery-drill.md`. Publish only sanitized copies and redact names, host identifiers, IPs outside this fictional lab, credentials, tokens and license details. Screenshots and real deployment evidence are intentionally absent until the operator runs the lab.

Interview topics: why DNS matters to AD, OU vs security group responsibilities, least privilege and protected objects, idempotence vs additive group changes, password handling, preflight vs transaction, state/drift limitations, ticket/session revocation limits, and AD-aware backup vs checkpoints.
