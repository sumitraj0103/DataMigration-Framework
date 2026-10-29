import json
from pathlib import Path

def get_summary_path():
    """
    Get the path to the discovery summary JSON file.

    Returns:
        Path: The path to the discovery summary JSON file.
    """
    output_dir = Path(__file__).resolve().parent.parent
    outputs_dir = output_dir / "outputs" / "discovery"
    outputs_dir.mkdir(parents=True, exist_ok=True)
    return outputs_dir / "discovery-summary.json"


def load_discovery_summary():
    """
    Load the discovery summary from the JSON file.

    Returns:
        dict: The discovery summary data.
    """
    summary_path = get_summary_path()
    if not summary_path.exists():
        return {}

    with open(summary_path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_discovery_summary(summary):
    """
    Write the discovery summary to a JSON file.

    Args:
        summary (dict): The discovery summary data.
        output_file (str): Path to the output JSON file.
    """
    output_file = get_summary_path()

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=4)

    print(f"Discovery summary saved to {output_file}")

def add_subscription_access_summary(
        summary,
        access_summary
):
    """
    Add subscription access summary to the discovery summary.

    Args:
        summary (dict): The discovery summary data.
        access_summary (dict): The subscription access summary data.

    Returns:
        dict: Updated discovery summary with subscription access summary.
    """

    subscription = summary["Subscription"]
    if "subscription" not in summary:
        summary["Subscription"] = {}
    summary["Subscription"] = {
        "id": subscription["id"],
        "name": subscription["name"],
        "accessSummary": access_summary,
        "ResourceGroups": subscription["ResourceGroups"]
    }
    return summary

def add_resource_group_access_summaries(
        summary,
        filtered_rbac,
        subscription_id,
        calculate_resource_group_rbac_metrics
):
    """
    Add resource group access summaries to the discovery summary.
    """
    updated_resource_groups = []
    for resource_group in summary["Subscription"]["ResourceGroups"]:

        resource_group["accessSummary"] = (
            calculate_resource_group_rbac_metrics(
                filtered_rbac,
                subscription_id,
                resource_group["id"]
            )
        )
        updated_resource_groups.append({
            "id": resource_group["id"],
            "name": resource_group["name"],
            "environment": resource_group["environment"],
            "location": resource_group["location"],
            "accessSummary": resource_group["accessSummary"],
            "storageAccounts": resource_group["storageAccounts"]
        })
    summary["Subscription"]["ResourceGroups"] = updated_resource_groups
    return summary

def add_storage_account_access_summaries(
        summary,
        filtered_rbac,
        subscription_id,
        calculate_storage_account_rbac_metrics
):
    """
    Add storage account access summaries to the discovery summary.
    """
    for resource_group in summary["Subscription"]["ResourceGroups"]:
        updated_storage_accounts = []
        for storage_account in resource_group["storageAccounts"]:
            storage_account["accessSummary"] = (
                calculate_storage_account_rbac_metrics(
                    filtered_rbac,
                    subscription_id,
                    resource_group["id"],
                    storage_account["id"]
                )
            )
            updated_storage_accounts.append({
                "id": storage_account["id"],
                "name": storage_account["name"],
                "location": storage_account["location"],
                "kind": storage_account["kind"],
                "skuName": storage_account["skuName"],
                "isGen2": storage_account["isGen2"],
                "accessSummary": storage_account["accessSummary"],
                "containerCount": storage_account["containerCount"]
            })
        resource_group["storageAccounts"] = updated_storage_accounts
    return summary

def write_json(
        data,
        output_dir,
        filename
):
    output_file = (
        Path(output_dir) / filename
    )

    # records = rbac_data.fillna("N/A").to_dict(orient="records")

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, default=str)

    return output_file

def write_rbac_csv(df, output_dir, filename):
    output_file = (
        Path(output_dir) / filename
    )

    df.to_csv(output_file, index=False)

    return output_file
