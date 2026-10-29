from discovery.resource_graph import execute_resource_graph_query
import subprocess
import shutil
import json

def discover_event_grid_system_topics(subscription_id, naming_conventions):
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
    
    query = f"""
    Resources
    | where type == "microsoft.eventgrid/systemtopics"
    | where resourceGroup matches regex '{rg_regex}'
    | extend environment = case(
        resourceGroup contains '{environments["Development"]}', '{environments["Development"]}',
        resourceGroup contains '{environments["Test"]}', '{environments["Test"]}',
        resourceGroup contains '{environments["Acceptance"]}', '{environments["Acceptance"]}',
        resourceGroup contains '{environments["Production"]}', '{environments["Production"]}',
        'Unknown'
    )
    | where tostring(properties.topicType) =~ "Microsoft.Storage.StorageAccounts"
    | project
        systemTopicId = id,
        systemTopicName = name,
        resourceGroup,
        environment,
        sourceResourceId = tostring(properties.source),
        topicType = tostring(properties.topicType)
    """

    response = execute_resource_graph_query(
        subscription_id,
        query,
    )

    return response.data





def discover_event_grid_subscriptions(system_topics):

    az_cli = shutil.which("az")

    if not az_cli:
        raise RuntimeError(
            "Azure CLI was not found. "
            "Ensure Azure CLI is installed and available in PATH."
        )

    subscriptions = []

    for topic in system_topics:

        result = subprocess.run(
            [
                az_cli,
                "eventgrid",
                "system-topic",
                "event-subscription",
                "list",
                "--resource-group",
                topic["resourceGroup"],
                "--system-topic-name",
                topic["systemTopicName"],
                "--output",
                "json",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

        event_subscriptions = json.loads(
            result.stdout
        )

        for event_subscription in event_subscriptions:

            destination = (
                event_subscription.get("destination")
                or {}
            )

            trigger_name = None

            endpoint_base_url = destination.get("endpointBaseUrl")

            if endpoint_base_url:
                trigger_name = endpoint_base_url.split("/")[-1]

            dependency_type = "Unknown"

            if endpoint_base_url:
                if "datafactory" in endpoint_base_url:
                    dependency_type = "Datafactory"

            storage_account_name = topic["sourceResourceId"].rstrip("/").split("/")[-1]

            subscriptions.append(
                {
                    "environment": topic["environment"],
                    "resourceGroup": topic["resourceGroup"],
                    "storageAccountName": storage_account_name,
                    "sourceResourceId": topic["sourceResourceId"],
                    "systemTopicId": topic["systemTopicId"],
                    "systemTopicName": topic["systemTopicName"],
                    "eventSubscriptionId": event_subscription.get("id"),
                    "eventSubscriptionName": event_subscription.get("name"),
                    "eventDeliverySchema": event_subscription.get("eventDeliverySchema"),
                    "includedEventTypes": ", ".join(event_subscription.get("filter", {}).get("includedEventTypes", [])),
                    "subjectBeginsWith": event_subscription.get("filter", {}).get("subjectBeginsWith"),
                    "subjectEndsWith": event_subscription.get("filter", {}).get("subjectEndsWith"),
                    "destinationType": destination.get("endpointType"),
                    "endpointBaseUrl": destination.get("endpointBaseUrl"),
                    "triggerName": trigger_name,
                    "dependencyType": dependency_type,
                    "provisioningState": event_subscription.get("provisioningState"),
                }
            )

    return subscriptions





