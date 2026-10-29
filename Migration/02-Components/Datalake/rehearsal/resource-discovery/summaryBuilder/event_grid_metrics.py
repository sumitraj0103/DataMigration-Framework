import pandas as pd #type: ignore


def calculate_subscription_event_grid_metrics(
    event_grid_subscriptions
):
    df = pd.DataFrame(
        event_grid_subscriptions
    )

    return {
        "systemTopicCount": (
            df["systemTopicId"]
            .nunique()
        ),
        "eventSubscriptionCount": len(df),
        "triggerCount": df[["triggerName", "environment"]].drop_duplicates().shape[0],
        "storageAccountCount": (
            df["storageAccountName"]
            .nunique()
        ),
        "destinationTypes": (
            df["destinationType"]
            .value_counts()
            .to_dict()
        ),
        "dependencyTypes": (
            df["dependencyType"]
            .value_counts()
            .to_dict()
        )
    }

def calculate_resource_group_event_grid_metrics(
    event_grid_subscriptions,
    resource_group_name
):
    df = pd.DataFrame(
        event_grid_subscriptions
    )

    filtered = df[df["resourceGroup"].str.lower() == resource_group_name.lower()]

    return {
        "systemTopicCount": (
            filtered["systemTopicId"]
            .nunique()
        ),
        "eventSubscriptionCount": len(filtered),
        "triggerCount": filtered[["triggerName", "environment"]].drop_duplicates().shape[0],
        "storageAccountCount": (
            filtered["storageAccountName"]
            .nunique()
        )
    }

def calculate_storage_account_event_grid_metrics(
    event_grid_subscriptions,
    storage_account_name
):
    df = pd.DataFrame(
        event_grid_subscriptions
    )

    filtered = df[df["storageAccountName"].str.lower() == storage_account_name.lower()]

    return {
        "systemTopicCount": (
            filtered["systemTopicId"]
            .nunique()
        ),
        "eventSubscriptionCount": len(filtered),
        "triggerCount": filtered[["triggerName", "environment"]].drop_duplicates().shape[0],
    }
