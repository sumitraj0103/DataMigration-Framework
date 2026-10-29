# Data Lake Migration

## 1. Purpose

This project supports the discovery, replication, and migration rehearsal of Azure Data Lake resources.

The solution is split into three main areas:

- **Resource-discovery** – discovers the Data Lake structure, RBAC assignments, and migration-relevant information.
- **Replication** – recreates selected Data Lake resources and permissions in a target environment for migration rehearsal.
- **Shared** – contains configuration shared between Discovery and Replication.

The current implementation focuses primarily on:

- Resource Groups
- Storage Accounts
- Containers
- RBAC assignments
- Storage Account and directory replication
- RBAC migration rehearsal

Additional dependency discovery, including Event Grid and related Azure resources, can be added incrementally.

---

## 2. Project Structure

```text
rehearsal/
│
├── resource-discovery/
│   ├── discovery/
│   ├── analysis/
│   ├── planner/
│   ├── writers/
│   ├── outputs/
│   │   └── discovery/
|   |   └── analysis/
|   ├── summaryBuilder
|   |   └── summary_builder.py
│   ├── config_loader.py
│   ├── main.py
│   └── requirements.txt
│
├── replication/
│   ├── common/
│   │   ├── Functions/
│   │   ├── config.ps1
│   │   ├── authenticate.ps1
│   │   └── load-common.ps1
│   └── ...
│
├── shared/
│   └── naming-conventions.json
│
└── README.md
```

### Discovery

The `discovery` folder contains the Python-based Azure discovery and analysis functionality.

- `discovery/` – Azure resource and RBAC discovery logic.
- `analysis/` – queries and analysis performed against the generated discovery outputs.
- `planner/` – migration planning and decisions about what should be migrated, recreated, skipped, or handled separately.
- `writers/` – reusable output writers for Parquet, JSON, and CSV.
- `outputs/` – generated discovery and analysis artifacts.
- `summary_builder.py` – builds the human-readable discovery summary.
- `config_loader.py` – loads shared configuration.
- `main.py` – main Discovery entry point.

### Replication

The `replication` folder contains the PowerShell scripts used to recreate selected resources and permissions in the Sandbox environment.

This currently includes:

- Storage Account deployment
- Container deployment
- Selected directory replication
- RBAC assignment rehearsal

### Shared

The `shared` folder contains configuration used by both Python Discovery and PowerShell Replication.

`naming-conventions.json` is the central source for shared naming conventions and should be used instead of maintaining separate naming definitions in Python and PowerShell.

---

## 3. Prerequisites

Before running the project, ensure the following are installed:

- Python
- Azure CLI
- PowerShell
- Bicep / Azure CLI Bicep support
- Git

The user must already be authenticated with Azure CLI:

```powershell
az login
```

The appropriate Azure permissions must also be activated before running Discovery or Replication.

The Replication scripts contain subscription validation logic. If a different Azure subscription is currently selected, the existing authentication helper can switch the Azure CLI context to the expected subscription before continuing.

Discovery assumes that the user has already authenticated through Azure CLI.

---

## 4. Python Environment Setup

All Python resource-discovery commands should be executed from the:

```text
rehearsal/resource-discovery folder.
```

Navigate to the Discovery root folder:

```powershell
cd .\Datalake\rehearsal\resource-discovery
```

Create a Python virtual environment:

```powershell
python -m venv .venv
```

Activate the environment:

```powershell
.\.venv\Scripts\Activate.ps1
```

Install the required Python dependencies:

```powershell
python -m pip install -r requirements.txt
```

The virtual environment should be activated whenever running the Python Discovery or Analysis scripts.

To confirm that the correct Python environment is active:

```powershell
python -c "import sys; print(sys.executable)"
```

The returned path should point to:

```text
rehearsal\resource-discovery\.venv\Scripts\python.exe
```

---

## 5. Run Discovery

From the `resource-discovery` folder, activate the virtual environment if it is not already active:

```powershell
.\.venv\Scripts\Activate.ps1
```

Run:

```powershell
python main.py
```

Discovery collects the migration-relevant Azure resource structure and RBAC information.

The current discovery scope includes:

1. Resource Groups
2. Storage Accounts
3. Containers
4. RBAC assignments

Discovery uses the shared naming conventions to identify and filter resources relevant to the migration.

Generated artifacts are written under:

```text
resource-discovery/
└── outputs/
```

Detailed discovery datasets are stored primarily as Parquet files to support further analysis.

---

## 6. Discovery Outputs

Discovery produces detailed datasets for analysis together with a concise JSON summary.

The detailed outputs include datasets such as:

```text
resource_groups.parquet
storage_accounts.parquet
containers.parquet
rbac_assignments_all.parquet
rbac_assignments_migscoped.parquet
```

These files provide the detailed resource and RBAC inventories and can be queried using Python, pandas, or DuckDB.

The discovery summary provides a more concise representation of the environment:

```text
Subscription
└── Resource Groups
    └── Storage Accounts
        └── Containers
```

The summary is intended for quick review, while the Parquet datasets contain the detailed information required for analysis and migration planning.

---

## 7. RBAC Analysis

RBAC analysis is performed against the generated Parquet datasets rather than querying Azure repeatedly.

The analysis scripts are located under:

```text
resource-discovery/
└── Analysis/
```

For example:

```powershell
python .\analysis\explore_rbac.py
```

RBAC analysis can be used to:

- Filter assignments by environment.
- Filter assignments to migration-relevant Storage Accounts.
- Compare assignments across different Azure scopes.
- Identify principal types and principal names.
- Exclude Managed Identities where required for the rehearsal.
- Identify candidate permissions for migration.
- Export selected results to CSV or JSON.

RBAC metrics can also be generated using the relevant metrics script:

```powershell
python .\analysis\run_rbac_metrics.py
```

Analysis outputs should be treated separately from the underlying Discovery inventory.

---

## 8. RBAC Pilot Selection

A representative subset of RBAC assignments can be selected for the Sandbox migration rehearsal.

The selected pilot assignments are stored as:

```text
rbac-pilot-selected.json
```

The pilot is intended to validate that RBAC assignments discovered from the source environment can be correctly recreated against equivalent target scopes.

The pilot should contain representative assignment types rather than attempting to recreate every source permission immediately.

Managed Identities are currently handled separately from the initial RBAC rehearsal.

---

## 9. Storage Replication

Storage replication is implemented using PowerShell under:

```text
replication/
```

The replication scripts load common configuration and functions through:

```text
replication/common/load-common.ps1
```

Shared naming conventions are loaded from:

```text
shared/naming-conventions.json
```

Replication-specific settings remain in:

```text
replication/common/config.ps1
```

This keeps shared naming configuration separate from settings that control the replication process.

### Storage Account Deployment

The Storage Account deployment can first be validated using Azure What-If before making changes.

The deployment scripts recreate the required Storage Account structure and containers in the target Sandbox environment.

Always review the What-If result before performing an actual deployment.

---

## 10. Directory Replication

Directory replication supports selected Data Lake directories.

The current rehearsal configuration uses selected directories rather than automatically replicating the entire Data Lake.

Replication configuration is defined in the PowerShell configuration, including settings such as:

```text
Mode
ContentMode
SelectedDirectories
```

A dry-run should be performed before actual replication.

The dry-run verifies:

- Source Storage Account
- Target Storage Account
- Containers
- Selected directory paths
- Replication configuration

This provides a safe validation of the replication configuration before modifying the target environment.

---

## 11. RBAC Rehearsal

The RBAC rehearsal uses the assignments selected during Discovery and Analysis and recreates them against equivalent target scopes.

The process is:

```text
Discovery
    ↓
RBAC Parquet inventory
    ↓
RBAC analysis
    ↓
rbac-pilot-selected.json
    ↓
PowerShell RBAC rehearsal
    ↓
Target Sandbox RBAC assignments
```

The PowerShell script maps the source scope to the corresponding target scope while retaining the relevant:

- Principal
- Principal type
- Role definition
- Resource scope type

The target resource identifiers are expected to differ from the source and are therefore resolved for the target environment before creating the assignment.

Creating an RBAC assignment in the target does not remove or modify the equivalent source assignment.

RBAC creation requires sufficient Azure authorization. Where the executing identity does not have permission to create role assignments directly, an approved Azure DevOps pipeline/service connection may be used for the deployment.

---

## 12. Migration Planning

Migration decisions are maintained separately from raw Discovery results.

The `planner` area is intended to document whether discovered resources or dependencies should:

- Be migrated directly
- Be recreated in the target
- Be recreated automatically by another deployment process
- Be handled separately
- Be excluded from the migration scope

This distinction is particularly important for dependencies such as:

- Azure Data Factory
- Event Grid
- Function Apps
- Storage Queues
- Managed Identities
- Other application or platform dependencies

Discovery identifies what exists. The migration plan determines what should happen to it.

---

## 13. Current Scope and Next Steps

The current implementation provides the foundation for:

- Data Lake resource discovery
- RBAC discovery and analysis
- Storage Account replication
- Selected directory replication
- RBAC migration rehearsal
- Source-to-target scope mapping

The next dependency-discovery iterations can extend the solution to identify relationships such as:

```text
Storage Account
    ↓
Event Grid
    ↓
ADF / Function App / Queue / other destination
```

This will allow dependencies to be classified before deciding whether they should be explicitly migrated, recreated through another deployment process, or excluded from the Data Lake migration itself.

The migration approach should continue to be developed incrementally, validating each migration building block in Sandbox before applying it to the real environments.

