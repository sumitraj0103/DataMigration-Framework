# Testing Strategy

## How do we test?

This document describes the validation approach used throughout the DMAP Reconsolidation testing structure.

It defines how validation is performed during pipeline development, deployment and promotion across environments, together with the principles used to organise and maintain the testing documentation.

---

# Testing Approach

The testing structure follows a **catalogue and execution** model.

Reusable validation requirements are maintained within catalogue documents.

Execution documents record where validation has been performed, the applicable pipelines, the target environments and the validation outcome.

This approach:

- Promotes consistency across validation activities.
- Reduces duplicated documentation.
- Simplifies maintenance.
- Encourages reuse of common validation definitions.
- Supports future pipeline implementations with minimal documentation changes.

---

# Validation Lifecycle

Validation follows a defined sequence to confirm that the environment and deployed solution are ready before pipeline behaviour is tested.

```text
Deployment
│
├── Shared Environment Validation
│
├── Pipeline Release Validation
│
▼
Pipeline Technical Validation
│
▼
Pipeline Functional Validation
│
▼
Regression Validation
```

## Pipeline Development

New Azure Data Factory pipelines are developed and validated within a dedicated Sandbox environment before being promoted to the logical solution environments.

The Sandbox provides an isolated environment where developers can:

- Implement new pipelines.
- Perform iterative functional validation.
- Validate technical pipeline configuration.
- Resolve implementation issues before deployment.

Validation is typically performed in the following order.

```text
Sandbox
    │
    ▼
Pipeline Implementation
    │
    ▼
Functional Validation
    │
    ▼
Technical Validation
```

> **Note:** During development, functional and technical validation are often performed iteratively as the pipeline evolves. The sequence above represents the primary validation focus before a pipeline is considered ready for promotion.

Technical validation during pipeline development focuses on confirming that the Azure Data Factory implementation is configured correctly, including:

- Connectivity and authentication
- Linked Services and datasets
- Parameters and expressions
- Activities and activity dependencies
- Triggers
- Retry and failure handling
- Pipeline-level environment resolution and isolation
- Pipeline monitoring and diagnostics

Provisioning, resource configuration, access controls and environment-level isolation are validated separately through the deployment validation catalogue.

---

## Environment Promotion

Once a pipeline has been successfully validated within the Sandbox, it is promoted through the logical solution environments.

Validation should normally follow this sequence.

```text
Deployment
     │
     ▼
Deployment Validation
     │
     ▼
Technical Validation
     │
     ▼
Functional Validation
     │
     ▼
Regression Validation
```

Deployment validation confirms that the required solution components have been deployed and configured correctly.

Technical validation confirms that the deployed implementation is correctly configured.

Functional validation confirms that the deployed pipeline performs the required business functionality.

Regression validation confirms that previously validated functionality continues to operate correctly following the deployment.

---

# Testing Traceability

The testing structure separates reusable validation requirements from validation execution.

Each execution document references the corresponding catalogue document, providing a consistent and traceable relationship between validation definitions and execution records.

```text
Deployment Test Catalogue
            │
            ▼
Environment Deployment Validation

Pipeline Common Test Catalogue
            │
            ▼
Pipeline Test Cases

Regression Test Catalogue
            │
            ▼
Regression Validation
```

---

# Extending the Testing Structure

When introducing a new Azure Data Factory pipeline:

1. Reuse the existing `pipeline-common-test-catalogue.md` for common technical validation.
2. Create a new pipeline validation document using the naming convention:

   ```text
   adf-<PipelineName>-test-cases.md
   ```

3. Add the applicable regression validation entries to `regression-validation.md` using the reusable validation definitions contained within `regression-test-catalogue.md`.

Catalogue documents should only be updated when introducing new reusable validation requirements.

---

# Guiding Principles

The testing strategy follows these guiding principles:

- Develop and validate new pipelines within the dedicated Sandbox environment before promoting changes.
- Maintain logical isolation between environments to prevent unintended cross-environment impacts.
- Ensure environment-specific configuration and resource access remain consistent throughout the promotion process.
- Reuse common validation definitions wherever possible to promote consistency and reduce duplicated documentation.
- Separate reusable validation requirements from execution records to simplify maintenance and improve traceability.
- Keep the testing structure concise, maintainable and easy to extend.