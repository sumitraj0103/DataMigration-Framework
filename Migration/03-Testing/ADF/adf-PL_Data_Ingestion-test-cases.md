# ADF Pipeline PL_Data_Ingestion Test Cases

## Purpose

This document records the technical and functional tests applicable to **PL_Data_Ingestion**.

Reusable common technical tests are referenced by their Test ID from `adf-common-test-catalogue.md`. Pipeline-specific technical and functional tests are defined directly in this document.

Deployment validation is performed separately and is documented in the corresponding deployment validation document.

---

## Pipeline Summary

| Property | Value |
|----------|-------|
| Pipeline | PL_Data_Ingestion |
| Workflow Description | Copies source files, evaluates file eligibility using metadata lookup, stored procedure and filtering logic, copies eligible files to the destination Blob Storage location, removes successfully processed files from the source location and leaves non-eligible files in the source location. |
| Trigger Type | Blob Trigger |
| Source | Azure Blob Storage |
| Destination | Azure Blob Storage |
| Owner | Lennart |
| Last Updated | To be updated |

---

## Test Cases

| Test ID | Scope | Test Type | <div style="width: 250px;">Test Description</div> | <div style="width: 200px;">Applies To</div> | <div style="width: 250px;">Expected Result</div> | Testing Mode | DEV | TEST | ACC | PROD | Evidence / Comments |
|---|---|---|---|---|---|---|:---:|:---:|:---:|:---:|---|
| ADF-COM-001 | Common | Technical | Verify connectivity to required resources. | Blob Storage Linked Service; Metadata SQL Linked Service | Required connections are established successfully. | Debug | PASSED | Pending | Pending | Pending | Execute permission on store procedure is needed |
| ADF-COM-002 | Common | Verify that linked services are configured correctly. | Linked Services | Linked Service Configuration | Linked services reference the correct resources and authenticate successfully. | Debug | Debug:PASSED; Debug-Deployed:Pending | Pending | Pending | Pending | |
| ADF-COM-003 | Common | Technical | Verify pipeline parameters and expressions resolve correctly. | Pipeline Parameters | Parameters and expressions resolve correctly during execution. | Debug | PASSED | Pending | Pending | Pending | |
| ADF-COM-004 | Common | Technical | Verify environment isolation & multi-environment. | Environment-specific Azure Resources with multi-environment support | The pipeline accesses only resources belonging to the current environment, but can also support other environments dynamically. | Debug | Debug:PASSED; Debug-Deployed:Pending | Pending | Pending | Pending | |
| ADF-COM-005 | Common | Technical | Verify pipeline trigger execution. | Blob Storage Trigger | The trigger invokes the pipeline successfully. | Triggered Execution | Debug | Pending | Pending | Pending | Pending | |
| ADF-PL_DI-001 | Pipeline-specific | Functional | Verify the pipeline starts when a new file arrives in the configured source location. | Blob Storage Trigger | The pipeline starts once for each eligible incoming file. | Debug | Pending | Pending | Pending | Pending | |
| ADF-PL_DI-002 | Pipeline-specific | Functional | Verify pipeline activities are performed correctly. | Copy, Lookup, Stored Procedure, Filter and Delete Activities | Activities execute according to the pipeline design. | Debug | PASSED | Pending | Pending | Pending | |
| ADF-PL_DI-003 | Pipeline-specific | Technical | Verify the filtering expressions evaluate correctly and provides expecting results for both: Matching and unmatching filtering and lookup criteria. | Lookup Activity; Filter Activity | Files are classified correctly according to the configured filtering rules and are copied succesfully (leaving or deleting source files where applicable). | Debug | PASSED | Pending | Pending | Pending | |
| ADF-PL_DI-004 | Pipeline-specific | Technical | Verify the stored procedure receives the required pipeline parameters. | Stored Procedure Activity | The expected file name, source path and environment parameters are passed correctly to the stored procedure. | Debug | Pending | Pending | Pending | Pending | |
| ADF-PL_DI-005 | Pipeline-specific | Technical | Verify the metadata returned by the stored procedure is mapped correctly. | Stored Procedure Activity; Lookup Activity | Returned metadata is available to the filtering logic using the expected fields and values. | Debug | Pending | Pending | Pending | Pending | |
| ADF-PL_DI-006 | Pipeline-specific | Technical | Verify the target path and file name are dynamically resolved. | Target Dataset; Copy Activity | Each eligible file is written to the expected target path using the expected file name. | Debug | PASSED | Pending | Pending | Pending | |
| ADF-PL_DI-007 | Pipeline-specific | Functional | Simulate a failure while deleting a successfully copied source file. | Delete Activity | The target copy remains available, the source file remains and the deletion failure is recorded. | Debug | Pending | Pending | Pending | Pending | |
| ADF-PL_DI-008 | Pipeline-specific | Functional | Verify the integrity of a successfully copied file. | Source Blob Storage; Target Blob Storage | The copied file matches the source file in content, file name and expected metadata. | Debug | PASSED | Pending | Pending | Pending | |
| ADF-DEP-007 | Pipeline Deployment | Technical | Verify the Azure Data Factory pipeline artefact and all its dependencies has been deployed successfully. | Pipeline and all its dependencies: Linked services, triggers, datasets | The pipeline is available within the target Data Factory along with all its required dependencies. | Deploy | Pending | Pending | Pending | Pending | |
| ADF-DEP-008 | Trigger Deployment | Technical | Verify required triggers have been deployed and configured correctly, and that their state matches that with the original source ADF pipeline. | Triggers | Triggers are deployed and configured as expected. | Deploy | Pending | Pending | Pending | Pending | |
| ADF-DEP-009 | Pipeline Configuration | Technical | Verify pipeline-specific configuration, parameters and environment references have been deployed correctly. | Pipeline | Pipeline configuration resolves correctly for the target environment. | Deploy | Pending | Pending | Pending | Pending | |



---

# Validation Notes

This document records the validation performed specifically for the **PL_Data_Ingestion** pipeline.

The **Common** technical validation requirements are defined centrally within the **Pipeline Common Test Catalogue** and reused across all Azure Data Factory pipelines.

The **Pipeline-specific** validation captures implementation details and business behaviour unique to the **PL_Data_Ingestion** pipeline. These tests verify functionality that cannot be standardised across all pipelines.

---