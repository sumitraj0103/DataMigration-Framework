import json
import shutil
import subprocess


def discover_containers(storage_account_name, is_gen2):
    """
    Discover containers in the specified storage account.

    Args:
        storage_account_name (str): The name of the storage account.
        is_gen2 (bool): Indicates if the storage account is Gen2.

    Returns:
        list: A list of containers in the storage account.
    """
    az_path = shutil.which("az")

    if az_path is None:
        raise RuntimeError("Azure CLI (az) is not installed or not found in PATH.")

    try:
        if is_gen2:
            # For Gen2 storage accounts, use 'az storage fs directory list'
            result = subprocess.run(
                [
                    az_path,
                    "storage",
                    "fs",
                    "list",
                    "--account-name",
                    storage_account_name,
                    "--auth-mode",
                    "login",
                    "--output",
                    "json"
                ],
                capture_output=True,
                text=True,
                check=True,
            )
        else:
            # For non-Gen2 storage accounts, use 'az storage container list'
            result = subprocess.run(
                [
                    az_path,
                    "storage",
                    "container",
                    "list",
                    "--account-name",
                    storage_account_name,
                    "--auth-mode",
                    "login",
                    "--output",
                    "json"
                ],
                capture_output=True,
                text=True,
                check=True,
            )

        if result.returncode != 0:
            raise RuntimeError(
                f"Failed to discover containers for storage account {storage_account_name}. \n"
                f"Error: {result.stderr}\n"
                f"Output: {result.stdout}"
            )
        containers = json.loads(result.stdout)
        return containers

    except subprocess.CalledProcessError as e:
        print(f"Error discovering containers for storage account {storage_account_name}: {e}")
        return []