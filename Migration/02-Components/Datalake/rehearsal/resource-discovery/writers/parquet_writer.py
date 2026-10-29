import pandas as pd
from pathlib import Path

def write_rbac_assignments_parquet(rbac_assignments, is_raw):
    output_dir = Path(__file__).resolve().parent.parent / "outputs" / "discovery"
    output_dir.mkdir(parents=True, exist_ok=True)

    df = pd.DataFrame(rbac_assignments)

    df.to_parquet(
        output_dir / f"rbac_assignments{'_all' if is_raw else '_migscoped'}.parquet",
        index=False
    )

def write_discovery_parquet(
        resource_groups,
        storage_accounts,
        containers_by_storage_account
):
    rows = []

    resource_group_lookup = {
        rg["name"].lower(): rg
        for rg in resource_groups
    }

    for storage_account in storage_accounts:
        resource_group = resource_group_lookup.get(
            storage_account["resourceGroup"].lower()
        )

        if not resource_group:
            continue

        storage_account_name = storage_account["name"]

        containers = containers_by_storage_account.get(
            storage_account_name,
            []
        )

        for container in containers:
            container_name = container["name"]
            container_id = (
                f"{storage_account['id']}"
                f"/blobServices/default/containers/{container_name}"
            )

            rows.append(
                {
                    "environment": resource_group["environment"],
                    "resourceGroupId": resource_group["id"],
                    "resourceGroupName": resource_group["name"],
                    "storageAccountId": storage_account["id"],
                    "storageAccountName": storage_account_name,
                    "containerId": container_id,
                    "containerName": container_name,
                    "location": storage_account["location"],
                    "kind": storage_account["kind"],
                    "skuName": storage_account["skuName"],
                    "skuTier": storage_account["skuTier"],
                    "isGen2": bool(
                        storage_account.get("isGen2") or False
                    )
                }
            )

            df = pd.DataFrame(rows)

            output_dir = Path(__file__).resolve().parent.parent / "outputs" / "discovery"
            output_dir.mkdir(parents=True, exist_ok=True)

            df.to_parquet(
                output_dir / "discovery.parquet",
                index=False
            )


def write_event_grid_parquet(
    event_grid_subscriptions,
    output_dir
):
    df = pd.DataFrame(event_grid_subscriptions)

    output_path = (
        output_dir
        / "event_grid_subscriptions.parquet"
    )

    df.to_parquet(
        output_path,
        index=False
    )

    return output_path
