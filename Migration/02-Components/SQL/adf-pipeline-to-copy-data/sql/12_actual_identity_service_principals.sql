-- Test table for PL_LoadSourceToStaging (Use Case 1.0): actual_identity.servicePrincipals, matching
-- the real DMAP actual_identity schema shape (id/email/upn), seeded with sample rows for testing.
-- Idempotent: creates the schema/table only if missing, and only seeds dummy rows when empty, so
-- it is safe to run against the DMAP database on the Dev/tst/Acc/Prd SQL servers alike.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'actual_identity')
    EXEC('CREATE SCHEMA actual_identity');
GO

IF OBJECT_ID('actual_identity.servicePrincipals', 'U') IS NULL
BEGIN
    CREATE TABLE actual_identity.servicePrincipals
    (
        id    INT           NOT NULL CONSTRAINT PK_servicePrincipals PRIMARY KEY,
        email NVARCHAR(256) NULL,
        upn   NVARCHAR(113) NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM actual_identity.servicePrincipals)
BEGIN
    INSERT INTO actual_identity.servicePrincipals (id, email, upn)
    VALUES
        (1,  'Anjan.Sarkar@cognizant.com',      'Anjan.Sarkar_cognizant.com#EXT#@connect2dll.onmicrosoft.com'),
        (2,  '1234@connect2dll.onmicrosoft.com', '1234@connect2dll.onmicrosoft.com'),
        (3,  'carolin.berg@hdi.de',              'carolin.berg_hdi.de#EXT#@connect2dll.onmicrosoft.com'),
        (6,  'AAC.CreditReps@delagelanden.com',  'AAC.CreditReps@connect2dll.onmicrosoft.com'),
        (7,  'aacboothdisplay@delagelanden.com', 'aacboothdisplay@connect2dll.onmicrosoft.com'),
        (9,  'halima.aadan@dllgroup.com',        'AadanH@delagelanden.com'),
        (11, NULL,                               'aan@connect2dll.onmicrosoft.com'),
        (12, 'solve.aasland@dllgroup.com',       'AaslandSA@delagelanden.com');
END
GO
