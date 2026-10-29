import json
from pathlib import Path

def load_naming_conventions():
    """
    Load the naming conventions from a JSON file.

    Returns:
        dict: The naming conventions data.
    """
    PROJECT_ROOT = Path(__file__).resolve().parent.parent
    NAMING_CONVENTIONS_PATH = PROJECT_ROOT / "shared/naming-conventions.json"
    with open(NAMING_CONVENTIONS_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


