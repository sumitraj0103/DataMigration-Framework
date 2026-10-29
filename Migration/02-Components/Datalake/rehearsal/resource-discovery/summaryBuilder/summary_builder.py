
from summaryBuilder.event_grid_metrics import (
    calculate_subscription_event_grid_metrics,
    calculate_resource_group_event_grid_metrics,
    calculate_storage_account_event_grid_metrics
)

from analysis.rbac_metrics import calculate_subscription_rbac_metrics, calculate_resource_group_rbac_metrics, calculate_storage_account_rbac_metrics


def build_subscription_summary(subscription):
    """
    Build a summary of the subscription.

    Args:
        subscription (dict): The subscription data.

    Returns:
        dict: A summary of the subscription.
    """
    return {
        "id": subscription["id"],
        "name": subscription["name"],
        "rbacAccessSummary": {},
        "eventGrid": {},
        "ResourceGroups": []
    }

def build_resource_group_summary(resource_group):
    """
    Build a summary of the resource group.

    Args:
        resource_group (dict): The resource group data.

    Returns:
        dict: A summary of the resource group.
    """
    return {
        "id": resource_group["id"],
        "name": resource_group["name"],
        "environment": resource_group["environment"],
        "location": resource_group["location"],
        "rbacAccessSummary": {},
        "eventGrid": {},
        "storageAccounts": []
    }

def build_storage_account_summary(storage_account, containers):
    """
    Build a summary of the storage account.

    Args:
        storage_account (dict): The storage account data.

    Returns:
        dict: A summary of the storage account.
    """
    return {
        "id": storage_account["id"],
        "name": storage_account["name"],
        "location": storage_account["location"],
        "kind": storage_account["kind"],
        "skuName": {
            "name": storage_account["skuName"],
            "tier": storage_account["skuTier"]
        },
        "isGen2": bool(storage_account["isGen2"] or False),
        "containerCount": len(containers)
    }

def build_file_summary(file):
    """
    Build a summary of the file.

    Args:
        file (dict): The file data.

    Returns:
        dict: A summary of the file.
    """
    return {
        "name": file["name"],
        "path": file["path"],
        "size": file["size"]
    }

def build_discovery_summary(subscription, resource_groups, storage_accounts, containers_by_storage_account, normalized_rbac, filtered_rbac, event_grid_subscriptions):
    """
    Build a summary of the discovery process.

    Args:
        subscription (dict): The subscription data.
        resource_groups (list): A list of resource groups.
        storage_accounts (list): A list of storage accounts.
        containers_by_storage_account (dict): A dictionary mapping storage account names to their containers.
        normalized_rbac (list): A list of normalized RBAC assignments.
        filtered_rbac (list): A list of filtered RBAC assignments.
        event_grid_subscriptions (list): A list of event grid subscriptions.

    Returns:
        dict: A summary of the discovery process.
    """
    subscription_summary = build_subscription_summary(subscription)

    subscription_summary["rbacAccessSummary"] = calculate_subscription_rbac_metrics(normalized_rbac)

    subscription_summary["eventGrid"] = calculate_subscription_event_grid_metrics(event_grid_subscriptions)

    for resource_group in resource_groups:
        resource_group_summary = build_resource_group_summary(resource_group)

        resource_group_summary["rbacAccessSummary"] = calculate_resource_group_rbac_metrics(
            filtered_rbac,
            subscription["id"],
            resource_group["id"]
        )

        resource_group_summary["eventGrid"] = calculate_resource_group_event_grid_metrics(
                    event_grid_subscriptions,
                    resource_group["name"]
                )

        for storage_account in storage_accounts:
            if storage_account["resourceGroup"].lower() != resource_group["name"].lower():
                continue
            storage_account_name = storage_account["name"]
            containers = containers_by_storage_account.get(storage_account_name, [])
            storage_account_summary = build_storage_account_summary(storage_account, containers)
            storage_account_summary["rbacAccessSummary"] = calculate_storage_account_rbac_metrics(
                filtered_rbac,
                subscription["id"],
                resource_group["id"],
                storage_account["id"]
            )

            storage_account_summary["eventGrid"] = calculate_storage_account_event_grid_metrics(
                            event_grid_subscriptions,
                            storage_account_name
                        )
            resource_group_summary["storageAccounts"].append(storage_account_summary)
            

        subscription_summary["ResourceGroups"].append(resource_group_summary)

    return {
        "Subscription": subscription_summary
    }