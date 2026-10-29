import pandas as pd  # type: ignore
from pathlib import Path

from analysis.rbac_metrics import calculate_rbac_metrics

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "outputs" / "discovery"

def main():
    rbac_analysis = pd.read_parquet(
        OUTPUT_DIR / "rbac_assignments_migscoped.parquet"
    )

    rbac_metrics = calculate_rbac_metrics(rbac_analysis)

    for metric, value in rbac_metrics.items():
        print(f"{metric:<20} {value}")
if __name__ == "__main__":
    main()