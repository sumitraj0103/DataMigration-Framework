from discovery.resource_graph import execute_resource_graph_query

def discover_resource_groups(subscription_id, naming_conventions):
    """
    Discover resource groups in the specified subscription.

    Args:
        subscription_id (str): The Azure subscription ID.
        naming_conventions (dict): The naming conventions data.

    Returns:
        list: A list of resource groups matching the pattern.
    """

    company_code = naming_conventions["CompanyCodePrefix"]
    resource_type = naming_conventions["ResourceTypes"]["ResourceGroup"]
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


    rg_regex = (
        rf"(?i).*{company_code}-"
        rf"{resource_type}-"
        rf"{team}-"
        rf"({environment_regex}).*"
    )

    # rg_condition = f"name matches regex @'{rg_regex}'"

    print("Company Code:", company_code)
    print("Resource Type:", resource_type)
    print("Team:", team)
    print("Environments:", environments)
    # print("Patterns:", resource_groups_patterns)
    print("Resource Group Condition:", rg_regex)

    query = f"""
    ResourceContainers
    | where type == 'microsoft.resources/subscriptions/resourcegroups'
    | where name matches regex @'{rg_regex}'
    | extend environment = case(
        name contains '{environments["Development"]}', '{environments["Development"]}',
        name contains '{environments["Test"]}', '{environments["Test"]}',
        name contains '{environments["Acceptance"]}', '{environments["Acceptance"]}',
        name contains '{environments["Production"]}', '{environments["Production"]}',
        'Unknown'
    )
    | project id, name, location, environment
    """

    resource_groups = execute_resource_graph_query(subscription_id, query)

    return resource_groups.data
