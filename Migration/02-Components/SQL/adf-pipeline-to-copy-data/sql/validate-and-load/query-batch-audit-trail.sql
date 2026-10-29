-- Ad-hoc lookup: shows every audit/log row tied to a given BatchId, across the master pipeline
-- run and the validate/load framework. Set @BatchId below and run all batches.

DECLARE @BatchId UNIQUEIDENTIFIER = 'PASTE-BATCH-ID-HERE';

SELECT * FROM mig.MasterRun       WHERE BatchId = @BatchId;
SELECT * FROM mig.StagingLoadRun  WHERE BatchId = @BatchId;

SELECT * FROM mig.ValidationRun   WHERE BatchId = @BatchId;
SELECT ve.*
FROM mig.ValidationError ve
INNER JOIN mig.ValidationRun vr ON vr.ValidationRunId = ve.ValidationRunId
WHERE vr.BatchId = @BatchId;

SELECT * FROM mig.LoadRun         WHERE BatchId = @BatchId;
