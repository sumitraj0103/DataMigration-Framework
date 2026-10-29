-- Generic single-database creator. Azure SQL requires CREATE DATABASE to be the ONLY statement
-- in its batch, so this file must be run once per database with -Variable DbName=<name>, and only
-- for databases that don't already exist (deploy.ps1 checks existence first).
CREATE DATABASE $(DbName);
