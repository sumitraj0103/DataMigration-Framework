import json
import shutil
import subprocess
# from subscriptions import get_current_subscription

def discover_rbac_assignments(subscription_id):
    """
    Discover RBAC assignments in the specified subscription.

    Args:
        subscription_id (str): The ID of the subscription.

    Returns:
        list: A list of RBAC assignments.
    """
    az_path = shutil.which("az")

    if az_path is None:
        raise RuntimeError("Azure CLI (az) is not installed or not found in PATH.")

    subscription_scope = f"/subscriptions/{subscription_id}"

    try:
        result = subprocess.run(
            [
                az_path,
                "role",
                "assignment",
                "list",
                "--all",
                "--fill-role-definition-name",
                "true",
                "--output",
                "json"
            ],
            capture_output=True,
            text=True,
            check=True,
        )

        if result.returncode != 0:
            raise RuntimeError(
                f"Failed to discover RBAC assignments for subscription {subscription_id}. Error: {result.stderr}"
            )

        rbac_assignments = json.loads(result.stdout)
        return rbac_assignments

    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"An error occurred while discovering RBAC assignments: {e.stderr}") from e

def normalize_rbac_assignment(assignment, subscription_id):
    """
    Normalize an RBAC assignment to a consistent format.

    Args:
        assignment (dict): The RBAC assignment to normalize.
        subscription_id (str): The ID of the subscription.

    Returns:
        dict: The normalized RBAC assignment.
    """
    scope = assignment.get("scope", "")
    scope_info = parse_rbac_scope(scope)


    normalized_assignment = {
        "assignmentId": assignment.get("id"),
        "principalId": assignment.get("principalId"),
        "principalType": assignment.get("principalType"),
        "principalName": assignment.get("principalName") or "Unknown",
        "roleDefinitionId": assignment.get("roleDefinitionId"),
        "roleName": assignment.get("roleDefinitionName"),
        "scope": assignment.get("scope"),
        "scopeType": scope_info["scopeType"],
        "subscriptionId": subscription_id,
        "resourceGroupId": scope_info["resourceGroupId"],
        "resourceGroupName": scope_info["resourceGroupName"],
        "storageAccountId": scope_info["storageAccountId"],
        "storageAccountName": scope_info["storageAccountName"],
        "containerId": scope_info["containerId"],
        "containerName": scope_info["containerName"],
        "condition": assignment.get("condition"),
        "conditionVersion": assignment.get("conditionVersion")
    }

    return normalized_assignment

def normalize_rbac_assignments(assignments, subscription_id):
    """
    Normalize a list of RBAC assignments to a consistent format.

    Args:
        assignments (list): The list of RBAC assignments to normalize.
        subscription_id (str): The ID of the subscription.

    Returns:
        list: A list of normalized RBAC assignments.
    """
    return [
        normalize_rbac_assignment(
            assignment, 
            subscription_id
        ) 
        for assignment in assignments
    ]


def parse_rbac_scope(scope):
    """
    Parse the RBAC scope to extract the resource group and storage account names.

    Args:
        scope (str): The RBAC scope string.

    Returns:
        tuple: A tuple containing the resource group name and storage account name, if present.
    """
    scope_info = {
        "scopeType": "Unknown",
        "resourceGroupId": None,
        "resourceGroupName": None,
        "storageAccountId": None,
        "storageAccountName": None,
        "containerId": None,
        "containerName": None
    }

    if not scope:
        return scope_info

    parts = scope.strip("/").split("/")

    parts_lower = [part.lower() for part in parts]

    # Resource group scope
    if "resourcegroups" in parts_lower:
        rg_index = parts_lower.index("resourcegroups")

        if rg_index + 1 < len(parts):
            resource_group_name = parts[rg_index + 1]
            scope_info["resourceGroupName"] = resource_group_name.upper()
            scope_info["resourceGroupId"] = (
                "/" + "/".join(parts[:rg_index + 2])
            )

            if rg_index + 2 == len(parts):
                scope_info["scopeType"] = "ResourceGroup"

    # Storage account scope
    if "storageaccounts" in parts_lower:
        sa_index = parts_lower.index("storageaccounts")

        if sa_index + 1 < len(parts):
            storage_account_name = parts[sa_index + 1]
            scope_info["storageAccountName"] = storage_account_name.lower()
            scope_info["storageAccountId"] = (
                "/" + "/".join(parts[:sa_index + 2])
            )

            if sa_index + 2 == len(parts):
                scope_info["scopeType"] = "StorageAccount"

    # Container scope
    if "blobservices" in parts_lower and "containers" in parts_lower:
        blob_index = parts_lower.index("blobservices")
        container_index = parts_lower.index("containers")

        if blob_index + 1 < len(parts) and container_index + 1 < len(parts):
            container_name = parts[container_index + 1]
            scope_info["containerName"] = container_name.lower()
            scope_info["containerId"] = (
                "/" + "/".join(parts[:container_index + 2])
            )

            if container_index + 2 == len(parts):
                scope_info["scopeType"] = "Container"

    # Subscription scope
    if (
        scope_info["scopeType"] == "Unknown"
        and len(parts) == 2
        and parts_lower[0] == "subscriptions"
    ):
        scope_info["scopeType"] = "Subscription"

    if scope_info["scopeType"] == "Unknown":
        scope_info["scopeType"] = "Other"

    return scope_info

def filter_rbac_by_discovery(normalized_rbac, discovery):
    """
    Filter normalized RBAC assignments by discovery data.

    Args:
        normalized_rbac (list): The list of normalized RBAC assignments.
        discovery (pd.DataFrame): The discovery DataFrame containing resource information.

    Returns:
        list: A list of filtered RBAC assignments.
    """
    # Create an environment mapping from the discovery DataFrame
    env_mapping = {
        rg_id.lower(): env
        for rg_id, env in zip(
            discovery["resourceGroupId"],
            discovery["environment"]
        )
    }

    # Create a set of allowed resource group IDs from the discovery DataFrame
    allowed_rg_ids = set(
        discovery["resourceGroupId"].str.lower()
    )

    # Create a set of allowed storage account IDs from the discovery DataFrame
    allowed_sa_ids = set(
        discovery["storageAccountId"].str.lower()
    )

    # Create a set of allowed container IDs from the discovery DataFrame
    allowed_container_ids = set(
        discovery["containerId"].str.lower()
    )

    filtered_rbac = [
        assignment
        for assignment in normalized_rbac
        if (
            assignment["scopeType"] == "ResourceGroup"
            and assignment.get("resourceGroupId") 
            and assignment["resourceGroupId"].lower() in allowed_rg_ids
        )
        or (
            assignment["scopeType"] == "StorageAccount"
            and assignment.get("storageAccountId") 
            and assignment["storageAccountId"].lower() in allowed_sa_ids
        )
        or (
            assignment["scopeType"] == "Container"
            and assignment.get("containerId") 
            and assignment["containerId"].lower() in allowed_container_ids
        )
    ]

    for assignment in filtered_rbac:
        assignment["environment"] = env_mapping.get(
            assignment["resourceGroupId"].lower()
        )

    return filtered_rbac

def get_principal_categories():
    """
    Determine the category of a principal based on its type and ID.

    Args:
        principal_id (str): The ID of the principal.
        principal_type (str): The type of the principal.
    Returns:
        str: The category of the principal.
    """
    az_path = shutil.which("az")
    if not az_path:
        raise FileNotFoundError("az CLI not found in PATH")
    # result = subprocess.run(
    #     [
    #         az_path,
    #         "ad", "sp", "show",
    #         "--id", principal_id,
    #         "--query", "servicePrincipalType",
    #         "-o", "json"
    #     ],
    #     capture_output=True,
    #     text=True,
    #     check=True
    # )
    result = subprocess.run(
        [
            az_path,
            "ad", "sp", "list",
            "--all",
            "--query", "[].{id:id, displayName:displayName, servicePrincipalType:servicePrincipalType}",
            "-o", "json"
        ],
        capture_output=True,
        text=True,
        check=True
    )
    service_principals = json.loads(result.stdout)

    return {
        sp["id"].lower(): {
            "principalCategory": (
                "ManagedIdentity" 
                if sp["servicePrincipalType"] == "ManagedIdentity" 
                else "ServicePrincipal"
            ),
            "displayName": sp.get("displayName"),
        }
        for sp in service_principals
    }

def enrich_principal_categories(rbac_assignments):
    """
    Enrich RBAC assignments with principal categories.

    Args:
        rbac_assignments (list): A list of RBAC assignments.

    Returns:
        list: A list of RBAC assignments enriched with principal categories.
    """
    principal_categories = (
        get_principal_categories()
    )

    for assignment in rbac_assignments:

        principal_type = assignment.get("principalType")
        principal_id = assignment.get("principalId")

        if (principal_type == "ServicePrincipal" and principal_id):

            principal_info = principal_categories.get(principal_id.lower(), {"principalCategory": "Unknown", "displayName": None})
            assignment["principalCategory"] = principal_info["principalCategory"]
            if principal_info["displayName"]:
                assignment["principalName"] = principal_info["displayName"]
        else:
            assignment["principalCategory"] = principal_type

    return rbac_assignments
