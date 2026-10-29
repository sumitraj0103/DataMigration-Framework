def build_event_grid_dependencies(event_grid_subscriptions):
    storage_accounts = {}

    for subscription in event_grid_subscriptions:
        environment = subscription.get("environment")
        storage_account_name = subscription.get("storageAccountName")

        key = (environment, storage_account_name)

        if key not in storage_accounts:
            storage_accounts[key] = {
                "environment": environment,
                "storageAccountName": storage_account_name,
                "eventGridSubscriptions": []
            }

        storage_accounts[key]["eventGridSubscriptions"].append(
            {
                "name": subscription.get("eventSubscriptionName"),
                "eventType": subscription.get("includedEventTypes"),
                "endpointType": subscription.get("destinationType"),
                "triggerName": subscription.get("triggerName"),
                "SubjectBeginsWith": subscription.get("subjectBeginsWith"),
                "SubjectEndsWith": subscription.get("subjectEndsWith"),
                "DependencyType": subscription.get("dependencyType")
            }
        )

    return {
        "storageAccounts": list(storage_accounts.values())
    }