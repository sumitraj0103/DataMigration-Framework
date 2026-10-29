# DMAP Reconsolidation Testing Structure

## What is this?

This directory contains the testing structure for the **DMAP Reconsolidation** solution.

The testing structure provides a consistent way to document deployment, pipeline and regression validation across the solution and its logical environments. It separates reusable validation definitions from execution records, making the testing documentation easier to maintain, extend and reuse as new Azure Data Factory (ADF) pipelines are introduced.

This document provides an overview of the testing structure. Additional documents explain:

- **Why are we testing?** → `tests-context.md`
- **What are we testing?** → `tests-scope.md`
- **How is testing performed?** → `tests-strategy.md`
- **Where can I find each testing document?** → `tests-index.md`

---

# Directory Structure

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
│   └── adf-PL_Data_Ingestion-test-cases.md
│
└── regression/
    ├── regression-test-catalogue.md
    └── regression-validation.md
```

---

# Testing Structure Overview

The testing structure is organised into three complementary validation areas.

## Deployment Validation

Deployment validation confirms that the solution has been deployed and configured correctly within the target environment.

Documentation consists of:

- **deployment-test-catalogue.md** – Defines reusable deployment validation requirements.
- **environment-deployment-validation.md** – Records the deployment validation results for each logical environment.

---

## Pipeline Validation

Pipeline validation confirms that Azure Data Factory pipelines have been implemented correctly and perform the required business functionality.

Documentation consists of:

- **pipeline-common-test-catalogue.md** – Defines reusable technical validation requirements that may be applied across multiple pipelines.
- **adf-\<PipelineName\>-test-cases.md** – Records the technical and functional validation performed for an individual pipeline.

---

## Regression Validation

Regression validation confirms that previously validated functionality continues to operate correctly following deployments or changes.

Documentation consists of:

- **regression-test-catalogue.md** – Defines reusable regression validation requirements.
- **regression-validation.md** – Records the execution of regression validation for the applicable pipelines and environments.

---

# Documentation Structure

The testing documentation follows a catalogue and execution model.

| Document Type | Purpose |
|--------------|---------|
| **Catalogue Documents** | Define reusable validation requirements, expected outcomes and validation objectives. |
| **Execution Documents** | Record where validation has been performed, the environments tested, the applicable pipelines and the validation outcome. |

---

# Naming Conventions

| Document Type | Naming Convention | Example |
|---------------|-------------------|---------|
| Deployment Catalogue | `deployment-test-catalogue.md` | `deployment-test-catalogue.md` |
| Deployment Validation | `environment-deployment-validation.md` | `environment-deployment-validation.md` |
| Pipeline Catalogue | `pipeline-common-test-catalogue.md` | `pipeline-common-test-catalogue.md` |
| Pipeline Validation | `adf-<PipelineName>-test-cases.md` | `adf-PL_Data_Ingestion-test-cases.md` |
| Regression Catalogue | `regression-test-catalogue.md` | `regression-test-catalogue.md` |
| Regression Validation | `regression-validation.md` | `regression-validation.md` |

---

# Guiding Principles

The testing structure is based on the following principles:

- Maintain a consistent approach to validation documentation.
- Reuse validation definitions wherever possible.
- Separate reusable validation definitions from execution records.
- Minimise duplicated documentation.
- Keep testing documentation concise, maintainable and easy to extend.
- Support future solution enhancements with minimal changes to the testing structure.