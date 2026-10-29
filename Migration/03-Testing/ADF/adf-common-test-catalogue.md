# Pipeline Common Test Catalogue

## Purpose

This catalogue defines the reusable technical validation requirements applicable to Azure Data Factory (ADF) pipelines within the DMAP Reconsolidation solution.

Technical validation confirms that Azure Data Factory pipelines have been implemented and configured correctly before promotion through the logical environments.

The catalogue contains reusable validation definitions only. Validation execution is recorded separately within the individual pipeline test case documents.

---

# Pipeline Technical Validation Catalogue

| Test ID | Validation Category | Technical Validation | Expected Result | Testing Mode | Priority
|---------|----------------------|----------------------|-----------------|------------------|
| ADF-COM-001 | Connectivity | Verify that the pipeline can connect to all required resources. | All required connections are established successfully. | Debug, Debug-Deployed and/or Triggered Execution | Must-do |
| ADF-COM-002 | Linked Service Configuration | Verify that linked services are configured correctly. | Linked services reference the correct resources and authenticate successfully. | Debug, Debug-Deployed and/or Triggered Execution | Must-do |
| ADF-COM-003 | Parameters | Verify that pipeline parameters and expressions resolve correctly. | Parameters are correctly resolved during execution. | Debug, Debug-Deployed and/or Triggered Execution | Must-do |
| ADF-COM-004 | Environment Isolation | Verify that the pipeline resolves to the correct environment specific resources. | No unintended cross-environment resource access occurs. | Debug, Debug-Deployed and/or Triggered Execution | Must-do |
| ADF-COM-005 | Trigger | Verify that pipeline triggers execute as expected. | Triggers invoke the pipeline successfully. | Triggered Execution | Must-do |
| ADF-COM-006 | Retry Policies | Verify that retry behaviour is configured correctly. | Retry policies behave as expected during execution. | Debug, Debug-Deployed and/or Triggered Execution | Optional |
| ADF-COM-007 | Failure Handling | Verify that pipeline failures are handled correctly. | Failures are managed according to the pipeline design. | Debug, Debug-Deployed and/or Triggered Execution | Optional |
| ADF-COM-008 | Monitoring | Verify that pipeline execution can be monitored successfully. | Pipeline execution information is available for operational monitoring. | Debug, Debug-Deployed and/or Triggered Execution | Optional |
| ADF-COM-009 | Diagnostics | Verify that sufficient diagnostic information is available for troubleshooting. | Diagnostic information is captured for successful and failed executions. | Debug, Debug-Deployed and/or Triggered Execution | Optional |
| ADF-DEP-007 | Pipeline Deployment | Verify the Azure Data Factory pipeline artefact and all its dependencies has been deployed successfully. | The pipeline is available within the target Data Factory along with all its required dependencies. | Deploy | Must-do |
| ADF-DEP-008 | Trigger Deployment | Verify required triggers have been deployed and configured correctly, and that their state matches that with the original source ADF pipeline. | Triggers are deployed and configured as expected. | Deploy | Must-do |
| ADF-DEP-009 | Pipeline Configuration | Verify pipeline-specific configuration, parameters and environment references have been deployed correctly. | Pipeline configuration resolves correctly for the target environment. | Deploy | Must-do |

---

# Validation Notes

Technical validation focuses on confirming that the Azure Data Factory pipeline implementation has been configured correctly and is ready for deployment and execution.

Typical validation includes:

- Connectivity and authentication.
- Linked Service configuration.
- Parameters and expressions.
- Activities and activity dependencies.
- Triggers.
- Retry and failure handling.
- Pipeline-level environment resolution and isolation.
- Pipeline monitoring and diagnostics.

Technical validation does **not** verify the deployment or provisioning of Azure resources, access controls or environment configuration. These activities are performed separately through the deployment validation process.