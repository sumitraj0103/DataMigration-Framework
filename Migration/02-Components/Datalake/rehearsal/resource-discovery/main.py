from pathlib import Path
import pandas as pd # type: ignore

from discovery.event_grid import discover_event_grid_subscriptions, discover_event_grid_system_topics
from discovery.subscriptions import get_current_subscription
from config_loader import load_naming_conventions
from writers.output_writer import write_discovery_summary, write_json
from writers.parquet_writer import write_discovery_parquet, write_rbac_assignments_parquet, write_event_grid_parquet
from summaryBuilder.summary_builder import build_discovery_summary
from discovery.rbac import discover_rbac_assignments, normalize_rbac_assignments, filter_rbac_by_discovery, enrich_principal_categories
from discovery.discovery import discover_datalake_structure
from summaryBuilder.dependencies import build_dependencies
from discovery.data_factory import (
    discover_data_factories,
    discover_data_factory_dependencies
)
from analysis.rbac_strategy_review import build_rbac_strategy_review


OUTPUT_DIR = Path(__file__).resolve().parent / "outputs" / "discovery"

RUN_STRUCTURE = True
  
RUN_RBAC_ASSIGNMENTS = True

RUN_DEPENDENCY_DISCOVERY = True

def main():
    event_grid_subscriptions = []
    datalake_structure = None
    rbac_assignments = []
    normalized_rbac = []
    filtered_rbac = []

    naming_conventions = load_naming_conventions()
    

    subscription = get_current_subscription()

    if subscription is None:
        print("Error: Unable to get current subscription")
        return

    if RUN_STRUCTURE:
        datalake_structure = discover_datalake_structure(
            subscription["id"], 
            naming_conventions
        )

        write_discovery_parquet(
            datalake_structure["resource_groups"],
            datalake_structure["storage_accounts"],
            datalake_structure["containers_by_storage_account"]
        )

    if RUN_RBAC_ASSIGNMENTS:

        discovery = pd.read_parquet(
            OUTPUT_DIR / "discovery.parquet"
        )

        rbac_assignments = discover_rbac_assignments(subscription["id"])

        normalized_rbac = normalize_rbac_assignments(rbac_assignments, subscription["id"])

        enriched_rbac = enrich_principal_categories(normalized_rbac)

        write_rbac_assignments_parquet(
            enriched_rbac, is_raw=True
        )

        filtered_rbac = filter_rbac_by_discovery(
            enriched_rbac, discovery
        )
        
        write_rbac_assignments_parquet(
            filtered_rbac, is_raw=False
        )


    if RUN_DEPENDENCY_DISCOVERY:

        event_grid_system_topics = (
                discover_event_grid_system_topics(
                    subscription["id"],
                    naming_conventions,
            )
        )

        # Discover event grid subscriptions
        event_grid_subscriptions = (
            discover_event_grid_subscriptions(
                event_grid_system_topics
            )
        )

        # Discover Data Factory dependencies in the migration Resource Groups
        data_factories = discover_data_factories(
            subscription["id"]
        )

        data_factory_dependencies = discover_data_factory_dependencies(
            subscription["id"],
            data_factories
        )

        # Build human-readable dependency view
        dependencies = build_dependencies(
            event_grid_subscriptions,
            data_factory_dependencies
        )

        # TEMPORARY CHECK
        # resolved_triggers = set()
        # unresolved_triggers = set()

        # for storage_account in dependencies["storageAccounts"]:
        #     for event_grid in storage_account["eventGridSubscriptions"]:

        #         trigger_name = event_grid.get("triggerName")

        #         if not trigger_name:
        #             continue

        #         if event_grid["dataFactoryPipelines"]:
        #             resolved_triggers.add(trigger_name)
        #         else:
        #             unresolved_triggers.add(trigger_name)


        # discovered_adf_triggers = {
        #     dependency.get("triggerName")
        #     for dependency in data_factory_dependencies
        #     if dependency.get("triggerName")
        # }

        # missing_from_adf = {
        #     trigger_name
        #     for trigger_name in unresolved_triggers
        #     if trigger_name not in discovered_adf_triggers
        # }


        # print("\n--- ADF DEPENDENCY RESOLUTION ---")
        # print("Unique resolved triggers:", len(resolved_triggers))
        # print("Unique unresolved triggers:", len(unresolved_triggers))
        # print("Unique triggers discovered from ADF:", len(discovered_adf_triggers))
        # print(
        #     "Unresolved triggers completely missing from ADF discovery:",
        #     len(missing_from_adf)
        # )

        # print("\n--- UNRESOLVED EVENT GRID ENDPOINTS ---")

        # for event_grid_subscription in event_grid_subscriptions:

        #     trigger_name = event_grid_subscription.get("triggerName")

        #     if trigger_name in missing_from_adf:
        #         print(
        #             trigger_name,
        #             "->",
        #             event_grid_subscription.get("endpointBaseUrl")
        #         )

        # trigger_to_check = "triggerArchDmaptoBlob"

        # for item in event_grid_subscriptions:
        #     if item.get("triggerName") == trigger_to_check:
        #         print(
        #             item
        #         )

        
        # write_json(
        #     event_grid_dependencies,
        #     OUTPUT_DIR,
        #     "event-grid-dependencies.json"
        # )
        write_json(
            dependencies,
            OUTPUT_DIR,
            "dependencies.json"
        )

        # Write detailed event grid inventory
        write_event_grid_parquet(
            event_grid_subscriptions,
            OUTPUT_DIR
        )

        # Build RBAC strategy review based on the latest discovery
        build_rbac_strategy_review(
            strategy_path="../replication/rbac/rbac-migration-strategy.csv",
            discovered_rbacs_path="../resource-discovery/outputs/discovery/rbac_assignments_migscoped.parquet",
            output_path="../replication/rbac/rbac-migration-strategy-review.csv"
        )
    
    if datalake_structure:
        summary = build_discovery_summary(
            subscription, 
            datalake_structure["resource_groups"], 
            datalake_structure["storage_accounts"],
            datalake_structure["containers_by_storage_account"],
            normalized_rbac,
            filtered_rbac,
            event_grid_subscriptions
        )

        write_discovery_summary(summary)
       
if __name__ == "__main__":
    main()