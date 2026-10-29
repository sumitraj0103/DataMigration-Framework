# Environment Deployment Validation

## Purpose

This document records the execution of the deployment validation requirements defined within the **Deployment Test Catalogue**.

Deployment validation confirms that the required Azure resources, Azure Data Factory artefacts and supporting configuration have been deployed correctly before pipeline execution validation begins.

---

# Deployment Information (Optional section)

| Property | Value |
|----------|-------|
| Deployment / Release | Release-001 |
| Target Environment | TEST |
| Deployment Date | YYYY-MM-DD |
| Pipelines Included | PL_Data_Ingestion |
| Change Reference | CHG-XXXX |

---

# Deployment Validation

| Test ID | Deployment Scope | Validation | Applies To | Validation Frequency | DEV | TEST | ACC | PROD | Evidence | Notes |
|---------|------------------|------------|------------|----------------------|-----|------|-----|------|----------|-------|
| DEP-001 | Shared environment | Resource Deployment | Shared Azure resources | Once per environment and after infrastructure changes | Pending | Pending | Pending | Pending | | |
| DEP-002 | Shared environment | Configuration | Shared environment configuration | Once per environment and after configuration changes | Pending | Pending | Pending | Pending | | |
| DEP-003 | Shared environment | Security | RBAC assignments; Managed Identities | Once per environment and after access-control changes | Pending | Pending | Pending | Pending | | |
| DEP-004 | Shared environment | Access Controls | Storage ACLs and permissions | Once per environment and after ACL changes | Pending | Pending | Pending | Pending | | |
| DEP-005 | Shared environment | Environment Isolation | Shared Azure resources | Once per environment and after infrastructure changes | Pending | Pending | Pending | Pending | | |
| DEP-006 | Shared environment | Monitoring & Diagnostics | Azure Monitor; Diagnostic Settings | Once per environment and after monitoring changes | Pending | Pending | Pending | Pending | | |


---

# Validation Notes

This document records the execution of the deployment validation requirements defined within the **Deployment Test Catalogue**.

Deployment validation consists of two validation scopes:

### Shared Environment Validation

Shared environment validation verifies infrastructure and configuration that is reused across multiple Azure Data Factory pipelines, including:

- Azure resources
- Shared environment configuration
- RBAC assignments
- Managed identities
- Storage permissions and ACLs
- Environment isolation
- Monitoring and diagnostic settings

These validations are typically performed **once per environment** and repeated only when the relevant infrastructure or configuration changes.

### Pipeline Release Validation

Pipeline release validation verifies Azure Data Factory artefacts deployed as part of an individual pipeline release, including:

- Azure Data Factory pipelines
- Pipeline triggers
- Pipeline-specific configuration
- Environment-specific parameter and resource references

These validations are performed **for each pipeline deployment**.