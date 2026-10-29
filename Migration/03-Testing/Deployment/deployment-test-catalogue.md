# Deployment Test Catalogue

## Purpose

This catalogue defines the reusable deployment validation requirements for the DMAP Reconsolidation solution.

Deployment validation confirms that the required Azure resources, Azure Data Factory artefacts and supporting configuration have been deployed correctly before functional and technical pipeline validation begins.

The catalogue defines reusable deployment validation requirements only. Validation execution is recorded separately within the deployment validation document.

---

# Deployment Validation Catalogue

| Test ID | Deployment Scope | Validation Category | Deployment Validation | Expected Result |
|---------|------------------|---------------------|-----------------------|-----------------|
| DEP-001 | Shared environment | Resource Deployment | Verify all required Azure resources have been deployed successfully. | All required resources exist and are available. |
| DEP-002 | Shared environment | Configuration | Verify shared environment configuration has been applied correctly. | Shared configuration matches the deployment specification. |
| DEP-003 | Shared environment | Security | Verify RBAC assignments and managed identities have been configured correctly. | Required identities have the expected permissions. |
| DEP-004 | Shared environment | Access Controls | Verify required ACLs and storage permissions have been configured correctly. | Storage permissions match the deployment specification. |
| DEP-005 | Shared environment | Environment Isolation | Verify shared resources are isolated correctly for the target environment. | Shared resources cannot unintentionally access other environments. |
| DEP-006 | Shared environment | Monitoring & Diagnostics | Verify monitoring and diagnostic settings have been configured correctly. | Monitoring information is available for deployed resources. |


---

# Validation Notes

Deployment validation confirms that Azure resources and Azure Data Factory artefacts have been deployed correctly before execution testing begins.

Deployment validation includes two validation scopes:

**Shared environment validation**

Shared environment validation verifies resources and configuration that are reused across multiple Azure Data Factory pipelines, including:

- Azure resources
- Shared configuration
- RBAC assignments
- Managed identities
- Storage permissions
- Environment isolation
- Monitoring and diagnostics

These validations are typically performed once per environment and repeated only when the relevant infrastructure or configuration changes.

**Pipeline release validation**

Pipeline release validation verifies deployment of pipeline-specific artefacts, including:

- Azure Data Factory pipelines
- Triggers
- Pipeline parameters
- Environment-specific references

These validations are performed for each pipeline deployment.

Deployment validation does not verify pipeline execution behaviour. Functional and technical execution validation is performed separately using the Pipeline Test Cases.