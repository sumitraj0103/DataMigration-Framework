# Data Lake Migration Rehearsal – Execution Plan

# 1. Purpose

This execution plan describes the Data Lake migration rehearsal and tracks its progress from discovery through an automated Sandbox-to-Test-Environment move.

The rehearsal uses one representative Data Lake to prove the migration approach safely before applying it more broadly.

The main objectives are to:

- Understand what needs to be migrated.
- Reproduce a representative Data Lake in Sandbox A without affecting the source.
- Test how access and dependencies need to be handled.
- Automate the move from Sandbox A to the Test environment.
- Validate that the expected structure, access and behaviour remain correct after the move.
- Record the key findings and decisions that may affect the wider migration.

The approach is intentionally incremental: prove each important migration building block on a small scale, learn from the execution, and only then combine the pieces into the end-to-end rehearsal.

**Current Status:** In Progress

---

# 2. Rehearsal Scope

The rehearsal focuses on **one representative Data Lake** and only the components needed to prove the migration approach.

### In Scope

- One selected Storage Account. Currently `mscstadmapdev03`
- Selected containers and directory structure.
- A representative set of RBAC assignments.
- Representative ACLs for move validation. These will be randomly assigned manually
- One representative dependency. Event Grid
- Automated movement from Sandbox A to the Test environment.
- Post-move validation.

### Not Required for This Rehearsal

- Migration of every Data Lake.
- Reassignment of every RBAC permission.
- Full ACL migration automation.
- Complete dependency migration.
- Managed Identity migration.
- Production migration execution.

The rehearsal is considered representative when it contains enough real-world complexity to demonstrate that the migration approach works and to identify issues that need to be addressed before applying it more broadly.

**Current Status:** Scope Defined

---

# 3. Execution Principles

The rehearsal follows the following principles:

1. **Discover before reproducing**
   - Understand the source structure and access configuration before applying changes.

2. **Use Discovery to define migration scope**
   - Discovery identifies the resources that belong to the migration.
   - RBAC discovery may return additional resources and assignments that exist in the subscription but are not part of the migration.

3. **Preserve both complete and migration-scoped information**
   - Full RBAC discovery is retained for investigation and audit.
   - A migration-scoped RBAC dataset is generated using the Discovery results.

4. **Test representative cases first**
   - A small number of RBAC assignments and dependencies are sufficient to prove the mechanism.
   - The rehearsal does not require every production permission or dependency to be reproduced.

5. **Do not automatically reproduce questionable access**
   - Permissions are reviewed before being assigned in Sandbox.
   - Managed identities are handled separately.
   - Unknown or stale principals are not automatically reproduced.

6. **Learn through execution**
   - Scripts are executed against the Sandbox environment.
   - Errors and limitations encountered during execution are captured as rehearsal findings.
   - Automation is improved based on those findings.

---

# 4. Rehearsal Flow

The rehearsal progresses from understanding the source Data Lake to proving an automated move between two isolated Sandbox environments.

```text
Source Data Lake
      |
      v
Discover & Define
      |
      v
Build Sandbox A Replica
      |
      v
Rehearse Access
      |
      v
Rehearse a Dependency
      |
      v
Validate Sandbox A
      |
      v
Automated Move
Sandbox A --> Test Environment
      |
      v
Validate & Close
      |
      v
Rehearsal Complete
```

Each phase builds on the previous one. The rehearsal only moves forward once there is enough confidence that the current step works as expected.

**Current Status:** Access Rehearsal In Progress

---

# 5. Execution Phases

The Data Lake rehearsal is divided into a small number of execution phases. Each phase proves a specific migration capability before moving to the next one.

| Phase | Focus | Key Activities | Expected Outcome | Status |
|---|---|---|---|---|
| Phase 1 | Discovery & Baseline | Discover Data Lake structure, capture RBAC, define migration scope, generate summary and analytical outputs | Clear understanding of what is being migrated and the expected source configuration | In-progress |
| Phase 2 | Sandbox A Replica | Replicate selected Storage Account, containers and directory structure into Sandbox A | Representative Data Lake replica available for migration testing | Completed |
| Phase 3 | Access Rehearsal | Select representative RBAC assignments, automatically assign them in Sandbox A, and configure representative ACLs manually | RBAC reassignment mechanism proven and representative access configuration available | In Progress |
| Phase 4 | Dependency Rehearsal | Select at least one representative dependency, such as Event Grid, and reproduce/reconfigure it against the Sandbox replica | Dependency handling approach proven without requiring every dependency to be migrated | Planned |
| Phase 5 | Sandbox A Validation | Validate structure, selected RBAC, ACL behaviour and representative dependency before movement | Sandbox A becomes the validated source for the move rehearsal | Planned |
| Phase 6 | Automated Move | Automate movement of the rehearsed Data Lake from Sandbox A to the Test environment, including required scope/resource remapping | Repeatable migration mechanism proven between isolated environments | Planned |
| Phase 7 | Post-Move Validation | Compare the Test environment against the expected rehearsal baseline and document issues/findings | Evidence that the migration approach preserves the required configuration and is ready for further iteration | Planned |

---

## Phase 1 – Discovery & Baseline

**Goal:** Understand the source Data Lake and establish the expected migration baseline and boundaries.

### Activities

- Discover the relevant Resource Groups, Storage Accounts and containers.
- Capture the Data Lake structure in a reusable discovery output.
- Discover RBAC assignments and identify those relevant to the migration.
- Classify principals sufficiently to distinguish Managed Identities from other access types.
- Produce a simple summary of the discovered structure and access.

Discovery is used to define **what is being migrated**. Broader RBAC information is retained for investigation but does not automatically become part of the migration scope.

### Outcome

A clear baseline of the selected Data Lake, its structure and the RBAC assignments relevant to the migration.

**Exit criteria:**

- The Data Lake resources included in the migration are clearly identified.
- RBAC relevant to the migration can be distinguished from broader subscription RBAC.

Key outputs:

- `discovery.parquet`
- `discovery-summary.json`
- `rbac_assignments_all.parquet`
- `rbac_assignments_migscoped.parquet`
- `rbac-replication-report.json`

**Status:** Completed
---

### Phase 2 – Sandbox A Replica

**Goal:** Create a representative copy of the selected Data Lake in an isolated environment without affecting the source.

Activities:

- Deploy the target Storage Account.
- Reproduce the required Storage Account configuration.
- Reproduce selected containers.
- Reproduce the required directory structure.
- Use zero-content or zero-cost representations where possible.
- Validate that the expected structural components exist in Sandbox A.

The replica is not intended to reproduce every production workload or every file. It provides a sufficiently representative Data Lake on which migration behaviour can be tested safely.

**Exit criteria:**

- Selected Storage Account exists in Sandbox A.
- Required containers exist.
- Required directory structure exists.
- Structural configuration is sufficient for RBAC, ACL and dependency testing.

**Status:** Completed / In Progress. Dependency remains to be marked as complete.

---

## Phase 3 – Rehearse Access

**Goal:** Prove how representative Data Lake access can be recreated and validated in Sandbox.

### Activities

- Review the RBAC assignments relevant to the selected Data Lake.
- Select approximately 10 representative assignments covering different principals, roles and scope levels.
- Exclude Managed Identities from this initial test and handle them separately if required.
- Develop and execute a script to recreate the selected RBAC assignments in Sandbox A.
- Capture any issues encountered and refine the approach as needed.
- Manually configure representative ACLs on selected directories/files for later move validation.

The purpose is not to reproduce every permission. It is to prove the RBAC reassignment mechanism and establish enough representative access configuration for the end-to-end rehearsal.

### Outcome

A tested RBAC reassignment approach and representative access configuration in Sandbox A.

**Status:** In Progress – RBAC candidates identified; pilot assignments to be selected and reassignment script to be developed.


## Phase 3 – Access Rehearsal

**Goal:** Prove how representative Data Lake access can be recreated and validated in Sandbox.

### Activities

- Review the RBAC assignments relevant to the selected Data Lake.
- Select approximately 10 representative assignments covering different principals, roles and scope levels.
- Exclude Managed Identities from this initial test and handle them separately if required.
- Develop and execute a script to recreate the selected RBAC assignments in Sandbox A.
- Capture any issues encountered and refine the approach as needed.
- Manually configure representative ACLs on selected directories/files for later move validation.

The purpose is not to reproduce every permission. It is to prove the RBAC reassignment mechanism and establish enough representative access configuration for the end-to-end rehearsal.

### RBAC Pilot

The RBAC pilot will use the migration-scoped RBAC assignments identified during Discovery.

The selected pilot assignments should, where available, cover different combinations of:

- Users
- Groups
- Ordinary Service Principals
- Resource Group scope
- Storage Account scope
- Container scope
- Different RBAC roles

Managed Identities are intentionally excluded from this first pilot because they are associated with Azure resources and require separate treatment.

The pilot should use a small but representative set of assignments rather than attempting to recreate every migration-scoped RBAC assignment.

### RBAC Target Scope Mapping

The source RBAC `scope` cannot be reused directly in Sandbox because it references the source Azure resource ID.

The deployment script must determine the equivalent target scope based on the assignment hierarchy.

```text
Source RBAC assignment
        |
        v
Identify scopeType
        |
        +-- ResourceGroup
        |
        +-- StorageAccount
        |
        +-- Container
        |
        v
Identify equivalent Sandbox resource
        |
        v
Construct Sandbox target scope
        |
        v
Create RBAC assignment
```

The original source scope should remain available in the pilot input for so that existing principals access to the operational environment is retained, but the PowerShell deployment must construct the target Sandbox scope.

### Execution Approach

The rehearsal intentionally follows an iterative execution approach:

```text
Execute
   |
   v
Observe error or behaviour
   |
   v
Understand Azure requirement or limitation
   |
   v
Update automation
   |
   v
Execute again
```

Errors encountered during the pilot are considered useful rehearsal findings. The objective is to identify these issues with a small number of assignments before attempting broader RBAC automation.

### RBAC Validation

After each successful assignment, validate that:

- The expected principal received the role.
- The expected role was assigned.
- The assignment was created at the correct Sandbox scope.
- No source resource scope was accidentally reused.
- No additional permissions were introduced unintentionally.

The pilot is considered successful when the selected representative assignments can be recreated consistently using the automated process.

### ACL Rehearsal

ACLs will be treated differently from RBAC during this rehearsal.

No additional ACL discovery or automated reassignment framework will be developed as part of this iteration.

Instead, representative ACLs will be manually created against selected directories and/or files in Sandbox A.

The purpose is to create ACL configuration that can later be observed during the Sandbox A to Test Environment move.

This allows the rehearsal to answer:

> Are the representative ACLs preserved or otherwise handled as expected during the move?

without adding unnecessary ACL migration logic to the current scope.

### ACL Validation

Before the automated move, record the representative ACL configuration applied in Sandbox A.

After the move, compare the corresponding Test environment paths against that baseline.

### Key Outputs

The RBAC portion of this phase uses the following artifacts:

- `rbac-replication-report.json`
  - Human-readable list of RBAC assignments relevant to the selected rehearsal Data Lake.

- `rbac-pilot-candidates.json`
  - Temporary candidate list used to inspect suitable RBAC assignments for the pilot.

- `selected-pilot-rbacs.json`
  - Controlled input containing approximately 10 RBAC assignments selected for automated Sandbox assignment testing.

The ACL portion uses manually configured representative permissions rather than an automated ACL migration dataset.

### Exit Criteria

Phase 3 is complete when:

- Approximately 10 representative RBAC assignments have been selected.
- Managed Identities have been excluded from the initial pilot.
- The PowerShell RBAC assignment mechanism has been implemented.
- Source scopes can be mapped to the correct Sandbox target scopes.
- The selected RBAC assignments can be created successfully or any remaining limitations are clearly understood.
- Errors and findings encountered during execution have been documented.
- Representative ACLs have been manually configured in Sandbox A.
- The resulting access configuration is ready to be included in the later Sandbox A to Test Environment move rehearsal.

### Outcome

A tested RBAC reassignment approach and representative access configuration in Sandbox A.

**Status:** In Progress – RBAC candidates identified; pilot assignments to be selected and reassignment script to be developed. ACLs to be manually assigned and documented.


## Phase 4 – Rehearse a Dependency

**Goal:** Prove that the Data Lake can be migrated together with a resource that depends on it.

### Activities

- Select one representative dependency associated with the rehearsal Data Lake.
- Understand how it connects to the source Data Lake.
- Reproduce or reconfigure it in Sandbox A.
- Update any references so that it uses the Sandbox resources.
- Confirm that the dependency works as expected.

For the first rehearsal iteration, **Event Grid** is a suitable candidate because it provides a concrete example of a resource whose configuration may reference the Storage Account or another Storage resource.

The purpose is not to handle every dependency type, but to prove that dependencies can be included in the migration approach.

### Dependency Inventory

Dependencies are tracked in a single inventory so that newly discovered dependency types have a clear place to be recorded, rather than being handled ad hoc. Some rows describe what is reproduced in the Sandbox rehearsal; others (ADF trigger coordination, Azure DevOps pipeline repointing) are requirements for the actual migration execution into the Test environment and are covered in Section 7, not performed within Sandbox A/the rehearsal itself.

| Dependency | Owner/Team | Pre-Move Action | Post-Move Action | Status |
|---|---|---|---|---|
| Azure Data Factory pipelines (Event Grid subscription on the Storage Account) | ADF pipeline owning teams | Notify teams; confirm triggers are disabled before the move | Re-enable triggers and repoint to the migrated Data Lake | In rehearsal (Event Grid pilot) |
| Azure DevOps pipelines (DEV/TST/ACC referencing the Storage Account resource ID) | Pipeline/DevOps owners | Identify all pipeline variables/service connections referencing the source resource ID | Update pipeline variables/service connections to the new resource ID in the target Resource Group | Identified – not yet rehearsed |
| Storage Queues | TBD | TBD | TBD | Planned – further iteration |
| Key Vaults | TBD | TBD | TBD | Planned – further iteration |
| Other Dependencies (open question) | TBD | TBD | TBD | To be identified during rehearsal/discovery |

This table should be updated as further dependency types are identified so the "other dependencies" question stays tracked rather than open-ended.

### Execution Approach

The important part of the rehearsal is understanding which parts of the dependency configuration are portable and which parts are environment-specific.

Examples of environment-specific information may include:

- Resource IDs
- Storage Account IDs
- Queue endpoints
- Event Grid scopes
- Resource Group names
- Managed Identity references
- Application configuration

Source resource identifiers must not be reused blindly when the dependency should reference the Sandbox replica.

### Initial Dependency Discovery

For the selected rehearsal Storage Account, identify the dependency that will be used for the pilot.

Capture enough information to understand:

- What the dependency is.
- Which source resource it references.
- How it interacts with the Data Lake.
- Which configuration would need to change in Sandbox.
- Whether additional resources are required for the dependency to operate.

This does not require building a complete dependency-discovery framework.

The immediate objective is to understand and reproduce one real dependency end-to-end.

### Event Grid Pilot

If Event Grid is selected as the representative dependency, inspect the relevant Event Grid configuration associated with the source Storage Account.

The rehearsal should determine:

- Which Event Grid subscription is relevant.
- Which Storage Account or resource acts as the event source.
- Which events are subscribed to.
- What the destination/endpoint is.
- Whether the destination also needs to exist in Sandbox.
- Which resource IDs or endpoints must be remapped.

The Sandbox version should reference the Sandbox resources rather than the original source resources.

Conceptually:

```text
Source Storage Account
        |
        v
Source Event Grid configuration
        |
        v
Identify required configuration
        |
        v
Map source resources
to Sandbox resources
        |
        v
Sandbox Storage Account
        |
        v
Sandbox Event Grid configuration
```

### ADF Trigger Coordination

Where the Event Grid subscription feeds one or more Azure Data Factory pipelines, the move must be coordinated with the teams owning those pipelines rather than handled as a purely technical remap.

This is a migration execution requirement, not a Sandbox A rehearsal activity: it applies when the Data Lake is actually moved into the Test environment (and later Production), not to the isolated Sandbox reproduction. It is documented here because it was identified during the dependency rehearsal.

The migration execution should:

- Identify the ADF pipelines whose triggers depend on the Storage Account's Event Grid subscription.
- Notify the owning teams ahead of the move.
- Confirm triggers are disabled before the move takes place.
- After the move, have the owning teams re-enable their triggers and repoint them to the migrated Data Lake.

This coordination step is a pre-move exit condition: the move should not proceed until the affected triggers are confirmed disabled.

### Azure DevOps Pipeline Repointing

Azure DevOps pipelines that reference the Storage Account's resource ID (for example through service connections, variables or variable groups for DEV, TST and ACC) do not follow the move automatically.

This is also a migration execution requirement rather than a Sandbox rehearsal step, since the DEV/TST/ACC pipelines only exist against the real environments.

The migration execution should:

- Identify the Azure DevOps pipelines, service connections and variables referencing the source Storage Account resource ID, per environment (DEV, TST, ACC).
- After the move, update those references to the new resource ID/Resource Group in the target production Resource Group.
- Confirm the updated pipelines run successfully against the migrated Data Lake before considering this dependency resolved.

This is a CI/CD configuration dependency rather than an Azure resource-to-resource dependency, and is handled separately from the Event Grid remap.

### Dependency Validation

After reproducing or reconfiguring the dependency in Sandbox A, validate that:

- The dependency exists in Sandbox A.
- It references the Sandbox Storage Account or other Sandbox resources.
- It does not unintentionally reference the original source resource.
- Required supporting resources exist.
- The configuration is structurally equivalent where appropriate.
- Basic behaviour can be demonstrated where practical.

Any differences that are intentionally environment-specific should be documented rather than treated as migration failures.

### Findings and Learning

Any issues encountered while reproducing the dependency should be added to the rehearsal findings and decisions log.

Examples may include:

- Resource IDs that require remapping.
- Dependencies that cannot be moved directly.
- Resources that must be recreated instead of moved.
- Managed Identity dependencies requiring separate treatment.
- Endpoint changes.
- Permissions required before a dependency can be recreated.
- Configuration that is owned by another deployment/release process.

These findings will determine what the later automated migration needs to handle.

### Exit Criteria

Phase 4 is complete when:

- At least one representative Data Lake dependency has been identified.
- The dependency's relationship with the source Data Lake is understood.
- Environment-specific references have been identified.
- The dependency has been reproduced or reconfigured in Sandbox A.
- The dependency references the correct Sandbox resources.
- Required supporting resources for the representative dependency are available.
- Basic configuration and behaviour have been validated.
- Issues and migration requirements discovered during the exercise have been documented.
- The dependency is ready to be included in the Sandbox A to Test Environment move rehearsal.
- The ADF trigger coordination and Azure DevOps pipeline repointing requirements (see Section 7) have been identified and documented for the actual migration execution.

### Outcome

One representative dependency working against the Sandbox A Data Lake and ready to be included in the automated move rehearsal.

**Status:** Planned


## Phase 5 – Validate Sandbox A

**Goal:** Confirm that Sandbox A contains everything needed for the end-to-end move rehearsal.

### Activities

Validate that the expected rehearsal components are present and working:

- Storage Account, containers and selected directory structure.
- Representative RBAC assignments.
- Representative ACLs.
- Representative dependency.

Any important differences or unresolved issues should be understood before proceeding.

### Move Readiness

The purpose of this validation phase is to answer:

> Is Sandbox A sufficiently complete and understood to act as the source for the automated migration rehearsal?

It is not necessary for Sandbox A to be an exact production replica.

It must instead contain the representative components required to prove the migration mechanism.

### Exit Criteria

Phase 5 is complete when:

- The selected Storage Account exists and has the expected rehearsal configuration.
- Expected containers exist.
- Required directory structure exists.
- Selected pilot RBAC assignments have been validated.
- RBAC assignments reference the correct Sandbox A scopes.
- Managed Identities remain outside the generic RBAC pilot.
- Representative ACLs have been recorded as a pre-move baseline.
- The representative dependency has been validated.
- Dependency configuration references the correct Sandbox A resources.
- Known differences and exceptions have been documented.
- No unresolved issue prevents the automated move from being meaningfully tested.
- Sandbox A has been accepted as the baseline for the Sandbox A to Test Environment move.

### Outcome

Sandbox A becomes the agreed baseline for the automated move to the Test environment.

**Status:** Planned


## Phase 6 – Automate Sandbox A to Test Environment

**Goal:** Prove that the validated Data Lake rehearsal can be moved between environments using a repeatable automated process.

### Activities

- Automate the move from Sandbox A to the Test environment.
- Recreate or preserve the selected Data Lake structure.
- Apply the RBAC approach proven during the access rehearsal.
- Handle the representative ACLs and dependency as required.
- Update environment-specific references so they point to the Test environment.
- Capture and resolve issues encountered during execution.

The purpose is to combine the migration building blocks proven in earlier phases into one end-to-end rehearsal.

### Define the Move Input

The automated process should use the known Sandbox A configuration as its source.

The move should determine:

- Source & Resource Groups
- Source & Target Storage Accounts
- Containers included in the rehearsal
- Required directory structure
- RBAC assignments included in the rehearsal
- Representative dependency
- Any resource mappings required between Sandbox A and the Test environment

Environment-specific values should be clearly separated from the migration logic.

The same automation should therefore be capable of operating with different source and target values without requiring the migration logic itself to be rewritten.

### Move the Data Lake Structure & Handle resource mapping

The purpose is to prove that the Data Lake structure can be transferred using the automated process. Resources created or moved into the Test environment may have different Azure resource identifiers from their Sandbox A equivalents.

### Recreate RBAC Assignments

Use the RBAC mechanism proven during Phase 3 to recreate the selected pilot assignments against the Test environment.

The process should:

1. Read the selected pilot RBAC assignments.
2. Identify the original assignment scope type.
3. Determine the equivalent Test environment resource.
4. Construct the Test environment target scope.
5. Create the role assignment.
6. Capture the result.

From ACLs, the purpose is to observe what happens to the representative ACL configuration during the move.

### Handle the Representative Dependency

The dependency proven during Phase 4 should also be handled during the Sandbox A to Test Environment move.

The automation should determine whether the dependency must be:

- Moved
- Recreated
- Reconfigured
- Repointed to the Test environment resource

Any Sandbox A resource references should be replaced with their Test environment equivalents where required.

### Failure Handling

The first version of the automation does not need to implement a sophisticated rollback framework.

However, failures must be visible and understandable.

The automation should avoid silently continuing when a required migration operation fails.

Where practical:

- Capture the failed operation.
- Capture the Azure error.
- Identify the affected resource.
- Continue only where doing so does not invalidate the remainder of the rehearsal.
- Record any manual recovery required.

The rehearsal environments provide the isolation required to safely investigate these failures.

### Repeatability

A key objective of this phase is to determine whether the process is repeatable.

The automation should avoid unnecessary hardcoded source-specific values.

Configuration such as:

```text
Source Resource Group
Source Storage Account
Target Resource Group
Target Storage Account
Selected Containers
```

should be provided as configuration or input rather than embedded throughout the migration logic.

This provides the foundation for later applying the same mechanism to other Data Lakes or environments.

### Outcome

The representative Data Lake and its required configuration are moved from Sandbox A to the Test environment through an automated and repeatable process.

**Status:** Planned

## Phase 7 – Validate & Close

**Goal:** Confirm that the automated move produced the expected result and determine whether the rehearsal has successfully proven the migration approach.

### Activities

Compare the Test environment against the validated Sandbox A baseline, focusing on:

- Data Lake structure.
- Representative RBAC assignments.
- Representative ACLs.
- Representative dependency.

Record any meaningful differences, lessons learned or limitations that could affect the wider migration.

### Rehearsal Evidence

At completion, retain the relevant rehearsal evidence.

This may include:

- `discovery-summary.json`
- `discovery.parquet`
- `rbac_assignments_all.parquet`
- `rbac_assignments_migscoped.parquet`
- `rbac-replication-report.json`
- `selected-pilot-rbacs.json`
- Deployment outputs
- Validation outputs
- Error logs
- Findings and decisions
- Dependency configuration used during the rehearsal

Temporary exploratory files such as candidate-selection outputs do not necessarily need to be retained permanently once the final pilot selection has been recorded.

### Outcome

A completed rehearsal with evidence that the migration approach works, or a clear understanding of what needs another iteration before applying it more broadly.

**Status:** Planned

# 6. Findings, Decisions and Exceptions Log

This section captures only findings that affect the migration approach, scope or future execution.  
Implementation and troubleshooting details are not tracked here.

| Area | Finding | Decision |
|---|---|---|
| Migration Scope | RBAC analysis identified permissions associated with Storage Accounts (`mscspikedev2sb`) inside the relevant Resource Groups that are not part of the selected Data Lake migration scope. | Keep these visible in the complete RBAC inventory (`rbac_assignments_all.parquet`) but exclude them from migration execution (`rbac_assignments_migscoped.parquet`). Discovery remains the source of truth for migration scope. |
| Principal Classification | Azure identifies Managed Identities and ordinary application Service Principals under the broader `ServicePrincipal` principal type. | Enrich RBAC with `principalCategory` so Managed Identities can be identified separately. |
| Unknown Principal | One unresolved Service Principal was identified in Production. | Retain it as `Unknown` for `principalCategory` column. No action is required for the current rehearsal because Production is not part of the current move. |
| Managed Identities | Managed Identities require resource-specific treatment (e.g. ADF triggers are deployed within each ADF instance) and should be handled separately. | Exclude Managed Identities from the initial RBAC reassignment rehearsal and address them separately when required. |
| RBAC Rehearsal | Reproducing every RBAC assignment is unnecessary to prove the reassignment mechanism. | Use approximately 10 representative assignments across different principal, role and scope types. |
| ACLs | Full ACL migration automation is not required to prove the current rehearsal. | Manually configure representative ACLs and verify their behaviour during the Sandbox A → Test Environment move. |
| Dependencies | Reproducing every dependency would make the first rehearsal unnecessarily broad. | Include one representative dependency in the first end-to-end rehearsal and expand only if required. |
| Dependencies | ADF pipelines use an Event Grid subscription on the Storage Account and must not be triggered mid-move. | Notify owning teams before the move, confirm triggers are disabled pre-move, and have teams re-enable/repoint triggers post-move. |
| Dependencies | Azure DevOps pipelines (DEV/TST/ACC) reference the Storage Account resource ID directly and will not follow the move automatically. | Identify affected pipelines/service connections and update the resource ID/Resource Group reference after the move, before those pipelines run again. |

### Key Decisions

The following decisions currently define the rehearsal scope:

- **Discovery defines migration scope.** RBAC discovery does not determine which resources are being migrated.
- **Full and migration-scoped RBAC are both retained.** The full dataset supports investigation; the filtered dataset supports migration execution.
- **Managed Identities are handled separately.** They are excluded from the initial RBAC reassignment pilot.
- **RBAC is tested using a representative sample.** Approximately 10 assignments are sufficient for the initial automation rehearsal.
- **ACL automation is out of scope for this rehearsal.** Representative ACLs will be configured manually and checked after the move.
- **Dependencies are introduced incrementally.** One representative dependency is sufficient for the first end-to-end rehearsal.
- **Sandbox execution drives learning.** Errors and limitations discovered during execution are added to this log and used to refine the migration process.

---

# 7. Migration Execution Checklist (Beyond Rehearsal Scope)

This section is separate from the Sandbox rehearsal above. It captures dependency-coordination steps that only apply when the Data Lake is actually moved into the Test environment (and later Production), not activities performed against Sandbox A/B.

**Pre-Move:**
1. Identify ADF pipelines dependent on the Storage Account's Event Grid subscription and notify owning teams.
2. Confirm ADF triggers are disabled.
3. Identify Azure DevOps pipelines/service connections (DEV, TST, ACC) referencing the source Storage Account resource ID.

**Move:** Execute the automated move of the Data Lake into the Test environment (Phase 6 mechanism).

**Post-Move:**
4. Update Azure DevOps pipeline variables/service connections to the new resource ID/Resource Group.
5. Have ADF pipeline owners re-enable triggers and repoint them to the migrated Data Lake.
6. Confirm repointed ADF triggers and Azure DevOps pipelines run successfully.


