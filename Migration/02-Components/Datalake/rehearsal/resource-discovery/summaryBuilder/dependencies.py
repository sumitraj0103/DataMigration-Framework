def build_dependencies(
    event_grid_subscriptions,
    data_factory_dependencies
):
    storage_accounts = {}

    # Build lookup of all discovered ADF triggers.
    # A trigger can have:
    # - one or more pipelines
    # - no pipeline (pipelineName = None)
    adf_lookup = {}

    for dependency in data_factory_dependencies:
        trigger_name = dependency.get("triggerName")

        if not trigger_name:
            continue

        key = trigger_name.strip().lower()

        if key not in adf_lookup:
            adf_lookup[key] = []

        adf_lookup[key].append(
            {
                "dataFactoryName": dependency.get("dataFactoryName"),
                "pipelineName": dependency.get("pipelineName")
            }
        )

    # Build Storage Account -> Event Grid -> ADF/Pipeline dependencies
    for subscription in event_grid_subscriptions:
        environment = subscription.get("environment")
        storage_account_name = subscription.get("storageAccountName")
        trigger_name = subscription.get("triggerName")

        storage_account_key = (
            environment,
            storage_account_name
        )

        if storage_account_key not in storage_accounts:
            storage_accounts[storage_account_key] = {
                "environment": environment,
                "storageAccountName": storage_account_name,
                "eventGridSubscriptions": []
            }

        # Determine ADF/pipeline resolution
        if trigger_name:
            trigger_key = trigger_name.strip().lower()

            if trigger_key in adf_lookup:
                pipelines = adf_lookup[trigger_key]

                # Trigger exists, but no pipeline is associated with it
                if all(
                    pipeline.get("pipelineName") is None
                    for pipeline in pipelines
                ):
                    pipelines = ["No Pipeline"]

            else:
                # Trigger was not found in any discovered/readable ADF
                pipelines = ["Unresolved"]

        else:
            pipelines = ["Unresolved"]

        storage_accounts[
            storage_account_key
        ]["eventGridSubscriptions"].append(
            {
                "name": subscription.get("eventSubscriptionName"),
                "eventType": subscription.get("includedEventTypes"),
                "endpointType": subscription.get("destinationType"),
                "triggerName": trigger_name,
                "subjectBeginsWith": subscription.get("subjectBeginsWith"),
                "subjectEndsWith": subscription.get("subjectEndsWith"),
                "dependencyType": subscription.get("dependencyType"),
                "dataFactoryPipelines": pipelines
            }
        )

    return {
        "storageAccounts": list(storage_accounts.values())
    }
