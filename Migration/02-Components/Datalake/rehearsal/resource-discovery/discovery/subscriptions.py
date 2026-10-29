import json
import shutil
import subprocess

def get_current_subscription():
    """
    Get the current Azure subscription ID and name.

    Returns:
        dict: The current subscription ID and name.
    """
    try:
        az_path = shutil.which("az")

        if az_path is None:
            raise RuntimeError("Azure CLI not found. Please install Azure CLI.")

        result = subprocess.run(
            [az_path, "account", "show", "--query", "{id:id,name:name}", "-o", "json"],
            capture_output=True,
            text=True,
            check=True,
        )
        subscription_info = json.loads(result.stdout)
        return {
            "id": subscription_info.get("id"),
            "name": subscription_info.get("name"),
            "tenantId": subscription_info.get("tenantId"),
        }
    except FileNotFoundError:
        print("Azure CLI not found. Please install Azure CLI.")
        return None
    except subprocess.CalledProcessError as e:
        print(f"Error retrieving current subscription: {e}")
        return None