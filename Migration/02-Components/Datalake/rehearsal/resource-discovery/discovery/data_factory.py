import requests  # type: ignore  # ensure 'requests' package is installed: pip install requests

from azure.identity import AzureCliCredential  # type: ignore[import-not-found]

from discovery.resource_graph import execute_resource_graph_query


def discover_data_factories(subscription_id):
    """
    Discover all Data Factory instances visible
    in the current subscription.
    """

    query = """
    Resources
    | where type =~ "microsoft.datafactory/factories"
    | project
        dataFactoryId = id,
        dataFactoryName = name,
        resourceGroup,
        location
    """

    response = execute_resource_graph_query(
        subscription_id,
        query
    )

    return response.data


def discover_data_factory_dependencies(
    subscription_id,
    data_factories
):
    """
    Retrieve ADF triggers and the pipelines referenced
    by those triggers.
    """

    credential = AzureCliCredential()

    token = credential.get_token(
        "https://management.azure.com/.default"
    )

    headers = {
        "Authorization": f"Bearer {token.token}"
    }

    dependencies = []

    for factory in data_factories:
        resource_group = factory["resourceGroup"]
        data_factory_name = factory["dataFactoryName"]

        # print(
        #     f"Reading ADF: {data_factory_name} "
        #     f"({resource_group})"
        # )

        url = (
            "https://management.azure.com/"
            f"subscriptions/{subscription_id}/"
            f"resourceGroups/{resource_group}/"
            "providers/Microsoft.DataFactory/"
            f"factories/{data_factory_name}/"
            "triggers?api-version=2018-06-01"
        )

        while url:
            response = requests.get(
                url,
                headers=headers
            )

            if not response.ok:
                print(
                    f"Failed reading ADF: "
                    f"{data_factory_name}"
                )

                print(
                    f"Status code: "
                    f"{response.status_code}"
                )

                print(
                    f"Azure error: "
                    f"{response.text}"
                )

                break

            response_data = response.json()

            for trigger in response_data.get(
                "value",
                []
            ):
                properties = trigger.get(
                    "properties",
                    {}
                )

                pipelines = properties.get("pipelines", [])

                if pipelines:
                    for pipeline in pipelines:
                        pipeline_reference = pipeline.get("pipelineReference", {})

                        dependencies.append(
                            {
                                "dataFactoryName": data_factory_name,
                                "triggerName": trigger.get("name"),
                                "pipelineName": pipeline_reference.get("referenceName")
                            }
                        )
                else:
                    dependencies.append(
                        {
                            "dataFactoryName": data_factory_name,
                            "triggerName": trigger.get("name"),
                            "pipelineName": None
                        }
                    )


            # Azure pagination
            url = response_data.get("nextLink")

    return dependencies

