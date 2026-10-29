# Regression Test Catalogue

## Purpose

This document defines the reusable regression validation tests for the Azure Data Factory (ADF) solution.

Regression validation verifies that previously validated functionality continues to operate correctly following pipeline, configuration or infrastructure changes.

This catalogue defines reusable regression validation patterns only. It does not identify specific pipelines, Azure resources or environments, and it does not record execution status or evidence.

The specific regression scope for each validation is defined in the corresponding regression validation documents.

---

## Regression Validation Tests

| Test ID | Validation Category | Regression Validation | Expected Result |
|----------|---------------------|-----------------------|-----------------|
| REG-001 | Trigger | Verify pipeline trigger functionality. | The pipeline trigger continues to operate correctly and initiates pipeline execution as expected. |
| REG-002 | Functional Processing | Verify successful end-to-end processing. | The primary processing workflow continues to produce the expected outcome. |
| REG-003 | Input Handling | Verify handling of ineligible input. | Input that does not satisfy the processing criteria continues to be handled correctly without unintended processing. |
| REG-004 | Failure Handling | Verify failure handling behaviour. | Processing failures continue to follow the configured error handling behaviour without unintended downstream actions. |
| REG-005 | Concurrent Functional Processing | Verify concurrent functional processing. | Multiple concurrent inputs continue to be processed correctly without omissions, duplicate processing or unintended behaviour. |
| REG-006 | Environment Isolation | Verify logical environment isolation. | Processing continues to use only the resources assigned to the intended logical environment. |
| REG-007 | Security | Verify security controls. | RBAC, ACLs and other security controls continue to enforce the intended access restrictions. |
| REG-008 | Monitoring | Verify monitoring and diagnostics. | Pipeline execution, activity status and diagnostic information continue to be available for operational monitoring and troubleshooting. |