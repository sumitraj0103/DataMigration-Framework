# Testing Index

## Where is everything?

This document provides an index of the testing documentation contained within the DMAP Reconsolidation testing structure.

It acts as a navigation guide to help locate reusable validation catalogues and validation execution documents.

---

# Testing Structure

```text
08-Testing/
│
├── README.md
├── tests-context.md
├── tests-scope.md
├── tests-strategy.md
├── tests-index.md
│
├── deployment/
│   ├── deployment-test-catalogue.md
│   └── environment-deployment-validation.md
│
├── pipelines/
│   ├── pipeline-common-test-catalogue.md
│   └── adf-<PipelineName>-test-cases.md
│
└── regression/
    ├── regression-test-catalogue.md
    └── regression-validation.md
```

---

# Core Documentation

| Document | Purpose |
|----------|---------|
| `README.md` | Overview of the testing structure and directory organisation. |
| `tests-context.md` | Explains why the testing structure has been created. |
| `tests-scope.md` | Defines the validation activities that are included and excluded. |
| `tests-strategy.md` | Describes how validation is performed and maintained. |
| `tests-index.md` | Provides an index of the testing documentation. |

---

# Deployment Validation

| Document | Purpose |
|----------|---------|
| `deployment-test-catalogue.md` | Reusable deployment validation requirements. |
| `environment-deployment-validation.md` | Records deployment validation performed within each logical environment. |

---

# Pipeline Validation

| Document | Purpose |
|----------|---------|
| `pipeline-common-test-catalogue.md` | Reusable technical validation requirements applicable to Azure Data Factory pipelines. |
| `adf-<PipelineName>-test-cases.md` | Records common and pipeline-specific validation for an individual Azure Data Factory pipeline. |

---

# Regression Validation

| Document | Purpose |
|----------|---------|
| `regression-test-catalogue.md` | Reusable regression validation requirements. |
| `regression-validation.md` | Records regression validation performed following deployments or implementation changes. |

---

# Naming Conventions

The following naming conventions should be used throughout the testing structure.

| Document Type | Naming Convention |
|--------------|-------------------|
| Pipeline validation | `adf-<PipelineName>-test-cases.md` |
| Deployment catalogue | `deployment-test-catalogue.md` |
| Deployment execution | `environment-deployment-validation.md` |
| Pipeline catalogue | `pipeline-common-test-catalogue.md` |
| Regression catalogue | `regression-test-catalogue.md` |
| Regression execution | `regression-validation.md` |

---

# Adding New Pipelines

When introducing a new Azure Data Factory pipeline:

1. Reuse the common technical validation requirements defined in `pipeline-common-test-catalogue.md`.
2. Create a new pipeline validation document using the standard naming convention:

   ```text
   adf-<PipelineName>-test-cases.md
   ```

3. Update `regression-validation.md` with the applicable regression validation entries for the new pipeline.

Catalogue documents should only be updated when introducing new reusable validation requirements.