from discovery.resource_graph import execute_resource_graph_query

def discover_storage_accounts(subscription_id, naming_conventions):
    """
    Discover storage accounts in the specified subscription.

    Args:
        subscription_id (str): The Azure subscription ID.
        naming_conventions (dict): The naming conventions data.

    Returns:
        list: A list of storage accounts matching the naming conventions.
    """

    company_code = naming_conventions["CompanyCodePrefix"]
    resource_type = naming_conventions["ResourceTypes"]["StorageAccount"]
    team = naming_conventions["Teams"]["DataManagementPlatform"]

    environments = naming_conventions["Environments"]

    source_environment_codes = [
        environments["Development"],
        # environments["Sandbox"], we skip sandbox for now, as we want to discover source environment
        environments["Test"],
        environments["Acceptance"],
        environments["Production"]
    ]

    environment_regex = "|".join(source_environment_codes)

    sa_regex = (
        rf"(?i).*{company_code}"
        rf"{resource_type}"
        rf"{team}"
        rf"({environment_regex})"
        rf"\d*$"
    ).lower()

    print("Company Code:", company_code)
    print("Resource Type:", resource_type)
    print("Team:", team)
    print("Environments:", environments)
    print("Storage Account Condition:", sa_regex)

    query = f"""
    Resources
    | where type =~ 'microsoft.storage/storageaccounts'
    | where name matches regex @'{sa_regex}'
    | project id, name, location, resourceGroup, kind, skuName= tostring(sku.name), skuTier= tostring(sku.tier), isGen2 = properties.isHnsEnabled
    """

    storage_accounts = execute_resource_graph_query(subscription_id, query)

    return storage_accounts.data