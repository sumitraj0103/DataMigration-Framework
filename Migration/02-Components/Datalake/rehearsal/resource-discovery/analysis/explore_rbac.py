import pandas as pd  # type: ignore

import duckdb  # type: ignore
from pathlib import Path
from writers.output_writer import write_json, write_rbac_csv

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "outputs" / "analysis"
RBAC_FILE = BASE_DIR / "outputs" / "discovery" / "rbac_assignments_migscoped.parquet"
RBAC_FILE_ALL = BASE_DIR / "outputs" / "discovery" / "rbac_assignments_all.parquet"

def get_all_rbac_assignments():
    """
    Returns a DataFrame of all RBAC assignments from the discovery outputs.
    """
    query = f"""
        SELECT *
        FROM '{RBAC_FILE_ALL.as_posix()}'
    """
    return duckdb.sql(query).df()

# --------------------------------
# 1. Migration Scoped RBAC Assignments
# -------------------------------
def get_migration_scoped_rbac_assignments():
    """
    Returns a DataFrame of RBAC assignments that are part of the migration scoped resource groups.
    """
    query = f"""
        SELECT *
        FROM '{RBAC_FILE.as_posix()}'
    """
    return duckdb.sql(query).df()

# --------------------------------
# 2. RBAC permissions relevant to Sandbox replica
# -------------------------------

SOURCE_RESOURCE_GROUP = ["MSC-RSG-DMAP-DEV"]
SOURCE_STORAGE_ACCOUNT = ["mscstadmapdev03"]
SOURCE_CONTAINER = ["raw", "curated"]

container_list = ", ".join([f"'{container.lower()}'" for container in SOURCE_CONTAINER])

def get_rbac_assignments_for_replication(source_resource_group: list, source_storage_account: list, source_containers: list):
    """
    Returns a DataFrame of RBAC assignments relevant to the replication of the specified resource group, storage account, and containers.
    """
    rg_list = ", ".join([f"'{rg.lower()}'" for rg in source_resource_group])
    sta_list = ", ".join([f"'{sa.lower()}'" for sa in source_storage_account])
    container_list = ", ".join([f"'{container.lower()}'" for container in source_containers])
    
    query = f"""
        SELECT
            environment,
            resourceGroupName,
            storageAccountName,
            containerName,
            scopeType,
            principalId,
            assignmentId,
            principalName,
            principalType,
            principalCategory,
            roleName,
            scope
        FROM '{RBAC_FILE.as_posix()}'
        WHERE
            lower(resourceGroupName) IN ({rg_list})\
            
            AND (
                lower(storageAccountName) IN ({sta_list})
                OR storageAccountName IS NULL
            )
            AND (
                lower(containerName) IN ({container_list})
                OR containerName IS NULL
            )
    ORDER BY
        scopeType,
        containerName,
        principalName,
        roleName
    """
    return duckdb.sql(query).df()

def select_pilot_rbac_candidates(pilot_rbac_candidates):
    """
    Returns a DataFrame of RBAC assignments that are candidates for pilot testing.
    """
    pilot_selection = [
        ("User", "ResourceGroup", "Reader"),
        # ("Group", "ResourceGroup", "Contributor"),
        # ("Group", "StorageAccount", "Storage Blob Data Owner"),
        # ("Group", "StorageAccount", "Storage Blob Data Reader"),
        # ("Group", "Container", "Storage Blob Data Contributor"),
        # ("Group", "ResourceGroup", "Reader"),
        ("ServicePrincipal", "ResourceGroup", "Owner"),
        ("ServicePrincipal", "StorageAccount", "Contributor"),
        ("ServicePrincipal", "StorageAccount", "EventGrid EventSubscription Write Only"),
        ("ServicePrincipal", "ResourceGroup", "EventGrid EventSubscription Write Only"),

        # ("Group", "ResourceGroup", "Key Vault Administrator")
    ]

    selected = []

    for principal_category, scope_type, role_name in pilot_selection:
        selected_candidates = pilot_rbac_candidates[
            (pilot_rbac_candidates['principalCategory'] == principal_category) &
            (pilot_rbac_candidates['scopeType'] == scope_type) &
            (pilot_rbac_candidates['roleName'] == role_name)
        ]

        if not selected_candidates.empty:
            selected.append(selected_candidates.iloc[[0]])  # Select the first candidate for each combination

    # Group candidates taht are not part of the Priviledge Identity Management Groups (These are excluded now, because there is an equivalent group in the target that will be used for identity reassignment after the move)
    group_candidates = pilot_rbac_candidates[
        (pilot_rbac_candidates['principalCategory'] == 'Group') 
        & (~pilot_rbac_candidates['principalName'].str.contains("PAG", case=False, na=False)) 
        & (pilot_rbac_candidates['scopeType'].isin(["StorageAccount", "Container"]))
    ]

    # Take a few representative group RBACS
    if not group_candidates.empty:
        selected.append(group_candidates.iloc[[0]])  # Select the first representative group RBAC

    if len(group_candidates) > 1:
        selected.append(group_candidates.iloc[[1]])  # Select the second representative group RBAC if available

    return pd.concat(selected) if selected else pd.DataFrame()

# --------------------------------
# 3. RBAC assignments with 'Unknown' principal category for migration scoped assignments
# -------------------------------
def get_unknown_principals_migscope():
    """
    Returns a DataFrame of RBAC assignments with 'Unknown' principal category within the migration scoped RBAC assignments.
    """
    query = f"""
        SELECT *
        FROM '{RBAC_FILE.as_posix()}'
        WHERE principalCategory = 'Unknown'
    """
    return duckdb.sql(query).df()

# --------------------------------
# 4. All RBAC assignments that are part of the migration scoped resource groups
# -------------------------------
def get_total_assignments_migscoped_rg():
    """
    Returns a DataFrame of all RBAC assignments that are part of the migration scoped resource groups.
    """
    query = f"""
        SELECT *
        FROM '{RBAC_FILE_ALL.as_posix()}' AS all_rbac
        WHERE all_rbac.resourceGroupName IN (
            SELECT DISTINCT resourceGroupName
            FROM '{RBAC_FILE.as_posix()}'
        )
    """
    return duckdb.sql(query).df()

# --------------------------------
# 5. RBAC assignments that are excluded from the migration scoped RBAC assignments
# --------------------------------
def get_excluded_rbac_assignments():
    """
    Returns a DataFrame of RBAC assignments that are excluded from the migration scoped RBAC assignments.
    """
    query = f"""
        SELECT *
        FROM '{RBAC_FILE_ALL.as_posix()}' AS all_rbac
        WHERE all_rbac.assignmentId NOT IN (
            SELECT DISTINCT assignmentId
            FROM '{RBAC_FILE.as_posix()}'
        )
        AND (
            all_rbac.resourceGroupName IN (
                SELECT DISTINCT resourceGroupName
                FROM '{RBAC_FILE.as_posix()}'
            )
        )
    """
    return duckdb.sql(query).df()

def get_rg_rbac_assignments():
    """
    Returns a DataFrame of RBAC assignments that are assigned at the resource group scope in the DEV environment.
    """
    query = f"""
        SELECT *
        FROM '{RBAC_FILE.as_posix()}'
        WHERE scopeType = 'ResourceGroup' and environment = 'DEV' and principalCategory NOT IN ('Unknown', 'ManagedIdentity')
    """
    return duckdb.sql(query).df()

def count_rbac_assignments_by_scope_type(rbac_df):
    """
    Returns a DataFrame with counts of RBAC assignments grouped by scopeType.
    """
    return rbac_df.groupby(["scopeType", "resourceGroupName"]).size().reset_index(name='count')

# # print("RBAC assignments by scopeType for migration scoped resource groups:", count_rbac_assignments_by_scope_type(get_migration_scoped_rbac_assignments()))

# rbac_df = get_migration_scoped_rbac_assignments()

# write_rbac_csv(rbac_df, OUTPUT_DIR, "rbac_assignments_all_filtered.csv")

# # --------------------------------
# # Pilot RBAC candidates filtering
# # --------------------------------
# # Get the rbac assignments relevant to the replication of the specified resource group, storage account, and containers
# replication_rbac = get_rbac_assignments_for_replication(SOURCE_RESOURCE_GROUP, SOURCE_STORAGE_ACCOUNT, SOURCE_CONTAINER)

# # Write the replication RBAC assignments to a JSON file
# rbac_records = replication_rbac.fillna("N/A").to_dict(orient="records")
# report_file = write_json(rbac_records, OUTPUT_DIR, "rbac-replication-report.json")

# # Select RBAC assignments that exclude 'Unknown' and 'ManagedIdentity' principal categories for pilot candidates
# pilot_rbac_candidates = replication_rbac[
#     replication_rbac['principalCategory'].isin(['ServicePrincipal', 'User', 'Group'])
# ]

# pilot_rbac_candidates_combinations = (
#     pilot_rbac_candidates.groupby(["principalCategory", "scopeType", "roleName"])
#     .size()
#     .reset_index(name='count')
# )

# print(pilot_rbac_candidates_combinations)

# # Write the pilot RBAC candidates to a JSON file
# pilot_file = write_json(pilot_rbac_candidates, OUTPUT_DIR, "rbac-pilot-candidates.json")

# # Count pilot candidates across principalCategory, scopeType, and roleName
# candidate_counts = pilot_rbac_candidates.groupby(["principalCategory", "scopeType", "roleName"]).size().reset_index(name='count')

# selected_rbac_candidates = select_pilot_rbac_candidates(pilot_rbac_candidates)
# # print(
# #     f"Selected pilot RBACs: "
# #     f"{len(selected_rbac_candidates)} out of {len(pilot_rbac_candidates)} candidates"
# # )

# write_json(
#     selected_rbac_candidates, OUTPUT_DIR, "rbac-pilot-selected.json"
# )

# #-----------------------------------------------------------------------------------------
# # General summary of RBAC migration scoped and excluded assignments
# all_rbac_assignments_migscoped_rg = get_total_assignments_migscoped_rg()
# excluded_rbac_assignments = get_excluded_rbac_assignments()
# migration_scoped_rbac_assignments = get_migration_scoped_rbac_assignments()
# print(f"All RBAC assignments part of migration scoped resource groups: {len(all_rbac_assignments_migscoped_rg)}")
# print(f"Excluded RBAC assignments from migration: {len(excluded_rbac_assignments)}")
# print(f"Migration Scoped total rbac assignments:{len(migration_scoped_rbac_assignments)}")


# dev_rg_rbac = get_rg_rbac_assignments()
# dev_rg_service_principals = dev_rg_rbac[dev_rg_rbac['principalCategory'] == 'ServicePrincipal'][["principalId", "principalName", "roleName"]].drop_duplicates()
# print(dev_rg_service_principals.to_string(index=False))

strategy = pd.read_csv("../replication/rbac/rbac-migration-strategy.csv")

rbacs = get_migration_scoped_rbac_assignments()

print("STRATEGY COLUMNS")
print(strategy.columns.tolist())

print("\nRBACS COLUMNS")
print(rbacs.columns.tolist())







