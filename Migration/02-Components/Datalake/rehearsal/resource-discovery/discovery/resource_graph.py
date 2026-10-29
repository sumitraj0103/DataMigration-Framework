# from azure.identity import DefaultAzureCredential
from azure.identity import AzureCliCredential
from azure.mgmt.resourcegraph import ResourceGraphClient
from azure.mgmt.resourcegraph.models import QueryRequest

# from Authentication.azure_auth import get_credential
# from Discovery.subscriptions import get_current_subscription


def execute_resource_graph_query(subscription_id,query):
    """
    Execute a Resource Graph query against a subscription.

    Args:
        subscription_id (str): The Azure subscription ID.
        query (str): The Resource Graph query to execute.

    Returns:
        dict: The query results from Azure Resource Graph.
    """
    if not subscription_id:
        raise ValueError("Subscription ID is required to execute the query.")
    if not query:
        raise ValueError("Query is required to execute the query.")

    credential = AzureCliCredential()
    client = ResourceGraphClient(credential)

    request = QueryRequest(
        subscriptions=[subscription_id],
        query=query,
    )

    response = client.resources(request)
    return response