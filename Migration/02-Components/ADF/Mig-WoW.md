# ADF Way of Working

## 1. ADF Current WoW

**Collaboration Branch:** master

**Publish branch:** adf_publish

**Workflow:**
1. Create feature branch from master --> change the pipeline --> Merge based on the PR (reviewed by internal) --> push the change to master --> publish to adf_publish
2. Create release and deploy to DEV --> TST --> ACC --> PRD

## 2. ADF WoW - During Migration

**Collaboration Branch:** mig_acceptance

**Publish branch:** mig_adf_publish { Branch out from adf_publish }

**Workflow per pipeline Change:**
1. Feature branch off mig_acceptance → PR → merge to mig_acceptance → publish to mig_adf_publish.
2. Deploy mig_adf_publish → Mig POC → validate.
3. Periodically forward-merge master → mig_acceptance to limit drift. [Except SP change --> No other change is expected]
4. Before final cutover: diff object inventories between master and mig_acceptance (names/definitions) and resolve collisions explicitly.
5. PR mig_acceptance → master (not the publish branches) → reviewed by DLL.
6. From ADF Studio, Publish master fresh → regenerates adf_publish.
7. Before deploying, run a diff of the new template's resources vs. each environment's live resources to catch unexpected deletions; ensure all triggers deploy in Stopped state.
8. Deploy DEV → validate -> Go/NoGo → TST → validate -> Go/NoGo → ACC → validate -> Go/NoGo → PRD, with rollback plan ready at each stage.
