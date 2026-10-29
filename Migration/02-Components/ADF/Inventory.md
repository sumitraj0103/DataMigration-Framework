# Inventory

This file lists all ADF pipelines found in the repository. Fill the `Migrate` and `Business critical` columns as appropriate.

| Pipeline name | Dependencies | Migrate | Business critical |
|---|---|:---:|---|
| PL_Data_Ingestion | LS_Database, DS_Landingzone_V2, DS_LandingZone, DS_DatalakestoreGen2_V2, DS_STA_BACKUP | Yes | P1 |
| PL_MOVE_BACKUP_TO_DR | DS_STA_BACKUP_RESTORE, DS_ADLS_DR | Yes | P4 |
| PL_UC_Metadata | DS_UC_Folder, DS_UC_Source, DS_Output_Destination | Yes | P3 | Runs only on Prod |
| PL_Azure_Resource_Insights_Weekly | DS_Azure_Resources_Insights_Raw, DS_Azure_Resources_Insights_SQL, DS_Azure_Resources_Insights_Raw_tabdelimited, LS_DMAP_SQL | Yes | P3 | Runs only on Prod |
| PL_DMAP_IGEG_DLS_AXWAY | LS_Database, DS_INPUT_DMAP_IGEG_API, DS_OUTPUT_DMAP_DLS_GEN2_AXWAY, DS_OUTPUT_DMAP_DLS_GEN2_AXWAY_BACKUP | No (Need confirmation)  |  |
| PL_MONITOR_0_Master |  | Yes | P3 |
| PL_MONITOR_1_LoadSqlTableGeneric | DS_ADLS_CSV, DS_ASQL |  Yes | P3 |
| PL_MONITOR_1_LoadStaging |   | Yes | P3 |
| PL_MONITOR_2_LoadDataMart |  | Yes | P3 |
| PL_MONITOR_2_LoadDmtGeneric | DS_ASQL, LS_DMAP_SQL | Yes | P3 |
| PL_MONITOR_Powerbi_Activities | DS_REST_POWERBI, DS_ADLS_CSV, DS_ADLS_JSON |  Yes | P3 |
| PL_MONITOR_Powerbi_Apps | DS_REST_POWERBI, DS_ADLS_CSV |  Yes | P3 |
| PL_MONITOR_Powerbi_Capacities | DS_REST_POWERBI, DS_ADLS_CSV |  Yes | P3 |
| PL_MONITOR_Powerbi_Dashboards | DS_REST_POWERBI, DS_ADLS_CSV |  Yes | P3 |
| PL_MONITOR_Powerbi_Dataflows | DS_REST_POWERBI, DS_ADLS_CSV |  Yes | P3 |
| PL_MONITOR_Powerbi_Forms | DS_Azure_Resources_Insights_Raw, DS_ASQL |  Yes | P3 |
| PL_MONITOR_Powerbi_Reports | DS_REST_POWERBI, DS_ADLS_CSV |  Yes | P3 |
| PL_MONITOR_Powerbi_SemanticModels | DS_REST_POWERBI, DS_ADLS_CSV |  Yes | P3 |
| PL_MONITOR_Powerbi_Workspaces | DS_REST_POWERBI, DS_ADLS_CSV |  Yes | P3 |
| PL_MONITOR_Powerbi_WorkspaceUsers | DS_REST_POWERBI, DS_ADLS_CSV | Yes | P3 |
| PL_COPY_DATA_CURATED_TO_ACC | DS_DatalakestoreGen2_Copy_Data, DS_STA_CURATED_COPY_DATA | No |  |
| PL_Ingest_FolderMapping_to_DB_STA | DS_STA_FOLDERMAPPING_Trigger, LS_DMAP_SQL, DS_STA_FOLDERMAPPING, DS_FolderMapping_Staging | No |  |
| PL_Data_Ingestion_ACC_PRD_V2 | LS_Database, DS_Landingzone_V2, DS_LandingZone, DS_DatalakestoreGen2_V2, DS_STA_BACKUP, DS_OUTPUT_DMAP_STA02_CHK | No |  |
| PL_Data_Ingestion_ACC_PRD_V3 | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| PL_Data_Ingestion_DTA_V2 | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| PL_Data_Ingestion_DEV_TST_V3 | LS_Database, DS_Landingzone_V2, DS_LandingZone, DS_DatalakestoreGen2_V2, DS_OUTPUT_DMAP_STA02_CHK | No |  |
| PL_Data_Ingestion_DEV_TST_V4 | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| PL_DMAP_IGEG_DLS_AXWAY_Old | LS_Database, DS_INPUT_DMAP_IGEG_API, DS_OUTPUT_DMAP_DLS_GEN2_AXWAY | No |  |
| PL_IF_BACKUP | LS_Database | No |  |
| PL_IF_BACKUP_V2 | LS_Database | No |  |
| PL_IF_RequiredCheck_DTA | LS_Database | No |  |
| PL_IF_RequiredCheck_PRD | LS_Database | No |  |
| PL_Ingest_FolderMapping_to_DB_STA_OLD | LS_DMAP_SQL, DS_STA_FOLDERMAPPING, DS_FolderMapping_Staging | No |  |
| PL_NonRequiredRows_DTA | DS_LandingZone, DS_DatalakestoreGen2, DS_OUTPUT_DMAP_STA02_CHK, LS_DMAP_STA02, LS_Database | No |  |
| PL_NonRequiredRows_DTA_FIX_1 | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| PL_NonRequiredRows_DTA_V2_copy1 | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| PL_NonRequiredRows_PRD | LS_Database, DS_LandingZone, DS_DatalakestoreGen2, DS_STA_BACKUP, DS_OUTPUT_DMAP_STA02_CHK, LS_DMAP_STA02 | No |  |
| PL_RequiredRows_DTA | LS_Database, DS_LandingZone, DS_DatalakestoreGen2, DS_OUTPUT_DMAP_STA02_CHK, LS_DMAP_STA02 | No |  |
| PL_RequiredRows_PRD | LS_Database, DS_LandingZone, DS_DatalakestoreGen2, DS_STA_BACKUP, DS_OUTPUT_DMAP_STA02_CHK, LS_DMAP_STA02 | No |  |
| Dummy | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| Dummy_TEST_2 | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| ExcludeCHKPipeline_WithRemovalOfCHK | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |
| ExcludeCHKPipeline_Working | LS_Database, DS_Landingzone_V2, DS_DatalakestoreGen2_V2 | No |  |

## Business critical classification

Use the following classification when completing the `Business critical` column.

| Classification | Business Impact | Recovery Requirement | Example |
|---|---|---|---|
| **Critical (P1)** | Production business stops if unavailable | Immediate recovery (minutes to <1 hour) | Customer-facing ingestion pipeline, finance data load |
| **High (P2)** | Major business impact but temporary workaround exists | Recover within a few hours | Daily operational reporting pipeline |
| **Medium (P3)** | Moderate impact | Recover within 1 business day | Internal analytics refresh |
| **Low (P4)** | Minimal impact | Recover when convenient | Historical backfill, archive jobs |

---

Next steps: if you want, I can auto-extract dataset/linked-service names into the `Dependencies` column for each pipeline.

