# Testing Scope

## What are we testing?

This document defines the scope of validation for the DMAP Reconsolidation solution.

It identifies the validation activities that are included within the testing structure, together with those that are explicitly excluded.

---

# In Scope

The testing structure covers the following validation activities.

## Deployment Validation

Validation of the deployment and configuration of shared solution resources, including:

- Resource deployment
- Environment-specific configuration
- Security configuration
- Access controls
- Environment isolation
- Monitoring and diagnostics

Deployment validation confirms that the target environment has been provisioned and configured correctly before pipeline validation is performed.

---

## Pipeline Validation

Validation of Azure Data Factory pipeline implementations, including:

### Functional Validation

Validation that pipelines perform the intended business process and satisfy the required functional behaviour.

### Technical Validation

Validation that Azure Data Factory pipelines have been implemented and configured correctly, including connectivity, authentication, pipeline configuration and execution behaviour.

Pipeline technical validation focuses on the Azure Data Factory implementation rather than the underlying services or infrastructure it depends upon.

---

## Regression Validation

Validation that previously verified functionality continues to operate correctly following deployments or implementation changes.

Regression validation provides confidence that new changes have not introduced unintended impacts to existing functionality.

---

# Logical Environments

Validation may be performed within the following logical environments.

| Environment | Purpose |
|------------|---------|
| DEV | Development and implementation validation. |
| TEST | Integration and system validation. |
| ACC | User acceptance and pre-production validation. |
| PROD | Production deployment validation. |

> Development and iterative validation are performed within a dedicated Sandbox environment as described in `tests-strategy.md`.

---

# Assumptions

The testing structure assumes that:

- The required solution components are available within the environment being validated.
- Environment-specific configuration has been completed.
- Required permissions are available.
- Representative test data is available where applicable.
- External systems required by the pipeline are available during validation.

---

# Out of Scope

The following activities are outside the scope of this testing structure.

## Infrastructure and Platform Validation

- Infrastructure provisioning outside the DMAP Reconsolidation solution.
- Azure platform validation.
- Network infrastructure validation.
- Operating system validation.

---

## External Systems

The testing structure verifies that Azure Data Factory pipelines can successfully interact with external systems, but does not validate the internal implementation of those systems.

Examples include:

- SQL database schema validation.
- SQL stored procedure business logic.
- Key Vault secrets management.
- API business logic.
- API functional testing.
- Data quality validation.
- Source and target data integrity validation.
- Payload content validation.
- Schema evolution or compatibility testing.

---

## Non-Functional Testing

The following validation activities are excluded:

- Performance testing.
- Load testing.
- Stress testing.
- Scalability testing.
- Security penetration testing.
- Vulnerability assessments.
- Disaster recovery testing.
- Business continuity testing.

---

## User Acceptance Testing

Business-led User Acceptance Testing (UAT) activities are outside the scope of this testing structure unless they directly support technical solution validation.