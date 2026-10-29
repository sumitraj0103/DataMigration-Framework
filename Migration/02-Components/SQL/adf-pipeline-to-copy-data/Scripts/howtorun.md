python compare_dev_prod_data.py --config-id 1 --dev-server msc-ssr-dmap-prd.database.windows.net --dev-database DMAP --prd-server msc-ssr-dmap-prd.database.windows.net --prd-database DMAP --only-in-dev


SELECT *
FROM mig_stg_dev.dbo_CI_AIC
WHERE [Instance Name] = '1099PR'
  AND [AIC Classification] = 311
  AND [Short Description] = '1099PRO'
  AND [Service Owner Name] = 'RF Default Workflow User'
  AND [Linked Application Owner] = 'RF Default Workflow User'
  AND ([Product Owner] = '' OR [Product Owner] IS NULL)
  AND [InsertDate] = '2023-11-08';