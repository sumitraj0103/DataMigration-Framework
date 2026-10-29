from discovery.resource_groups import discover_resource_groups
from discovery.storage_accounts import discover_storage_accounts
from discovery.containers import discover_containers

def discover_datalake_structure(
        subscription_id,
        naming_conventions
):
    """
    Discover the structure of a data lake in an Azure subscription.

    Args:
        subscription_id (str): The ID of the Azure subscription.
        naming_conventions (dict): A dictionary containing naming conventions for resource groups and storage accounts.

    Returns:
        dict: A dictionary containing the discovered resource groups, storage accounts, and containers.
    """
    resource_groups = discover_resource_groups(
        subscription_id, naming_conventions
    )

    storage_accounts = discover_storage_accounts(
        subscription_id, 
        naming_conventions
    )

    containers_by_storage_account = {}
    for storage_account in storage_accounts:
        storage_account_name = storage_account["name"]
        containers = discover_containers(storage_account_name, storage_account["isGen2"])
        containers_by_storage_account[storage_account_name] = containers

    return {
        "resource_groups": resource_groups,
        "storage_accounts": storage_accounts,
        "containers_by_storage_account": containers_by_storage_account
    }