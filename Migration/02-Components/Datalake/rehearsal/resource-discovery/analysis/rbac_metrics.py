def calculate_rbac_metrics(rbac_analysis):
    """
    Calculate RBAC metrics based on the provided RBAC analysis.

    Args:
        rbac_analysis (pd.DataFrame): The DataFrame containing the RBAC analysis.

    Returns:
        dict: A dictionary containing the calculated RBAC metrics.
    """
    total_assignments = len(rbac_analysis)
    unique_principals = rbac_analysis["principalId"].nunique()
    unique_roles = rbac_analysis["roleName"].nunique()

    metrics = {
        "totalDiscoveredAssignments": total_assignments,
        "uniquePrincipals": unique_principals,
        "uniqueRoles": unique_roles
    }

    return metrics

def calculate_subscription_rbac_metrics(normalized_rbac):
    """
    Calculate RBAC metrics for a specific subscription based on the provided normalized RBAC assignments.

    Args:
        normalized_rbac (list): A list of normalized RBAC assignments.
    """
    total_assignments = len(normalized_rbac)
    unique_principals = len(set(
        assignment.get("principalId") 
        for assignment in normalized_rbac
        if assignment.get("principalId") is not None
    ))
    unique_roles = len(set(
        assignment.get("roleName") 
        for assignment in normalized_rbac
        if assignment.get("roleName") is not None
    ))

    subscription_scoped_assignments = sum(
        1
        for assignment in normalized_rbac
        if assignment.get("scopeType") == "Subscription"
    )

    assignments_by_resource_group = {}

    for assignment in normalized_rbac:
        resource_group_name = assignment.get("resourceGroupName")
        if resource_group_name:
            resource_group_name = resource_group_name.upper()
            assignments_by_resource_group[resource_group_name] = (
                assignments_by_resource_group.get(resource_group_name, 0) + 1
            )

    metrics = {
        "totalDiscoveredAssignments": total_assignments,
        "uniquePrincipals": unique_principals,
        "uniqueRoles": unique_roles,
        "subscriptionScopedAssignments": subscription_scoped_assignments,
        "assignmentsByResourceGroup": assignments_by_resource_group
    }

    return metrics

def calculate_resource_group_rbac_metrics(filtered_rbac, subscription_id, resource_group_id):
    """
    Calculate RBAC metrics for a specific resource group based on the provided filtered RBAC assignments.

    Args:
        filtered_rbac (list): A list of filtered RBAC assignments.
        subscription_id (str): The ID of the subscription.
        resource_group_id (str): The ID of the resource group.
    Returns:
        dict: A dictionary containing the calculated RBAC metrics for the resource group.
    """
    
    resource_group_rbac = [
        assignment for assignment in filtered_rbac
        if assignment.get("subscriptionId")
        and assignment.get("subscriptionId").lower() == subscription_id.lower()
        and assignment.get("resourceGroupId")
        and assignment["resourceGroupId"].lower() == resource_group_id.lower()
    ]

    metrics = {
        "totalDiscoveredAssignments": len(resource_group_rbac),

        "uniquePrincipals": len({
            assignment["principalId"] 
            for assignment in resource_group_rbac
            if assignment.get("principalId") is not None
        }),

        "uniqueRoles": len({
            assignment["roleName"] 
            for assignment in resource_group_rbac
            if assignment.get("roleName") is not None
        }),

        "assignmentsByScopeType": {
            "ResourceGroup": sum(
                1 for assignment in resource_group_rbac
                if assignment.get("scopeType") == "ResourceGroup"
            ),
            "StorageAccount": sum(
                1 for assignment in resource_group_rbac
                if assignment.get("scopeType") == "StorageAccount"
            ),
            "Container": sum(
                1 for assignment in resource_group_rbac
                if assignment.get("scopeType") == "Container"
            )
        }

    }
    return metrics

def calculate_storage_account_rbac_metrics(
        filtered_rbac,
        subscription_id,
        resource_group_id,
        storage_account_id
):
    """
    Calculate RBAC metrics for a specific storage account based on the provided filtered RBAC assignments.

    Args:
        filtered_rbac (list): A list of filtered RBAC assignments.
        subscription_id (str): The ID of the subscription.
        resource_group_id (str): The ID of the resource group.
        storage_account_id (str): The ID of the storage account.
    Returns:
        dict: A dictionary containing the calculated RBAC metrics for the storage account.
    """
    storage_account_rbac = [
        assignment for assignment in filtered_rbac
        if assignment.get("subscriptionId")
        and assignment.get("subscriptionId").lower() == subscription_id.lower()
        and assignment.get("resourceGroupId")
        and assignment["resourceGroupId"].lower() == resource_group_id.lower()
        and assignment.get("storageAccountId")
        and assignment["storageAccountId"].lower() == storage_account_id.lower()
    ]

    metrics = {
        "totalDiscoveredAssignments": len(storage_account_rbac),

        "uniquePrincipals": len({
            assignment["principalId"] 
            for assignment in storage_account_rbac
            if assignment.get("principalId") is not None
        }),

        "uniqueRoles": len({
            assignment["roleName"] 
            for assignment in storage_account_rbac
            if assignment.get("roleName") is not None
        }),

        "assignmentsByScope": {
            "StorageAccount": sum(
                1 for assignment in storage_account_rbac
                if assignment.get("scopeType") == "StorageAccount"
            ),
            "Container": sum(
                1 for assignment in storage_account_rbac
                if assignment.get("scopeType") == "Container"
            )
        }
    }
    return metrics