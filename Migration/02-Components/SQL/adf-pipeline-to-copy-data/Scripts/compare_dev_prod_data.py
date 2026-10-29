"""
Compare staging/source data (DEV) against Production data (PRD) for a table, keyed by its
business key column(s), before running PL_ValidateAndLoadToProduction / usp_LoadValidatedTableToProduction.

This is a read-only sanity check: it does not modify either database.

Usage examples
--------------
Pull the table/key config straight from mig.TableConfiguration on the Prod server:

    python compare_dev_prod_data.py --config-id 1 ^
        --dev-server dmap-dev-sql.database.windows.net --dev-database DMAP ^
        --prd-server dmap-prd-sql.database.windows.net --prd-database DMAP

Or specify everything explicitly (no mig.TableConfiguration lookup):

    python compare_dev_prod_data.py ^
        --dev-server localhost --dev-database DMAP --dev-schema mig_stg_dev --dev-table dbo_CI_AIC ^
        --prd-server localhost --prd-database DMAP --prd-schema dbo --prd-table CI_AIC ^
        --business-keys "Instance Name,AIC Classification"

Authentication
--------------
Defaults to Azure Active Directory authentication (required for Azure SQL, which does not
support Windows/Trusted logins). The AAD token is acquired once via azure-identity
(InteractiveBrowserCredential, with MFA support) and reused for both connections, avoiding
the ODBC driver's own WAM broker popup, which frequently reports "User canceled sign in"
for console apps even after a successful login. For SQL auth, supply
--dev-user/--dev-password and/or --prd-user/--prd-password (or set the
DEV_SQL_USER/DEV_SQL_PASSWORD/PRD_SQL_USER/PRD_SQL_PASSWORD environment variables).

Requires: pip install pyodbc azure-identity
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
from dataclasses import dataclass
from functools import lru_cache
from typing import Optional

import pyodbc

SQL_COPT_SS_ACCESS_TOKEN = 1256
AAD_SCOPE = "https://database.windows.net/.default"


@lru_cache(maxsize=1)
def _get_aad_token_struct() -> bytes:
    """Acquire an AAD access token once (interactive login) and encode it for SQL_COPT_SS_ACCESS_TOKEN."""
    from azure.identity import InteractiveBrowserCredential

    credential = InteractiveBrowserCredential()
    token = credential.get_token(AAD_SCOPE).token
    token_bytes = token.encode("utf-16-le")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)


@dataclass
class ConnectionSettings:
    server: str
    database: str
    user: Optional[str] = None
    password: Optional[str] = None
    driver: str = "{ODBC Driver 18 for SQL Server}"

    def connection_string(self) -> str:
        parts = [
            f"DRIVER={self.driver}",
            f"SERVER={self.server}",
            f"DATABASE={self.database}",
            "Encrypt=yes",
            "TrustServerCertificate=no",
        ]
        if self.user:
            parts += [f"UID={self.user}", f"PWD={self.password}"]
        return ";".join(parts)

    def connect(self) -> pyodbc.Connection:
        if self.user:
            return pyodbc.connect(self.connection_string())
        # Azure SQL does not support Windows/Trusted logins; use an AAD access token instead.
        token_struct = _get_aad_token_struct()
        return pyodbc.connect(self.connection_string(), attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct})


def quote_ident(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def load_config_from_prod(conn: pyodbc.Connection, configuration_id: int):
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns
        FROM mig.TableConfiguration
        WHERE ConfigurationId = ?
        """,
        configuration_id,
    )
    row = cursor.fetchone()
    if row is None:
        raise SystemExit(f"ConfigurationId {configuration_id} not found in mig.TableConfiguration.")
    source_schema, source_table, target_schema, target_table, business_key_columns = row
    keys = [c.strip() for c in business_key_columns.split(",") if c.strip()]
    return source_schema, source_table, target_schema, target_table, keys


def fetch_rows(conn: pyodbc.Connection, schema: str, table: str):
    qualified = f"{quote_ident(schema)}.{quote_ident(table)}"
    cursor = conn.cursor()
    cursor.execute(f"SELECT * FROM {qualified}")
    columns = [c[0] for c in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    return columns, rows


def build_key(row: dict, key_columns: list[str]):
    return tuple(row.get(c) for c in key_columns)


def compare(dev_columns, dev_rows, prd_columns, prd_rows, key_columns: list[str]):
    common_columns = [c for c in dev_columns if c in prd_columns]
    missing_in_common = (set(dev_columns) ^ set(prd_columns))
    if missing_in_common:
        print(f"WARNING: DEV/PRD column sets differ: {sorted(missing_in_common)}", file=sys.stderr)

    dev_by_key = {build_key(r, key_columns): r for r in dev_rows}
    prd_by_key = {build_key(r, key_columns): r for r in prd_rows}

    dup_dev = len(dev_rows) - len(dev_by_key)
    dup_prd = len(prd_rows) - len(prd_by_key)
    if dup_dev:
        print(f"WARNING: {dup_dev} duplicate business-key rows found in DEV (last one wins in comparison).")
    if dup_prd:
        print(f"WARNING: {dup_prd} duplicate business-key rows found in PRD (last one wins in comparison).")

    only_in_dev = [k for k in dev_by_key if k not in prd_by_key]
    only_in_prd = [k for k in prd_by_key if k not in dev_by_key]
    mismatched = []

    for key in dev_by_key.keys() & prd_by_key.keys():
        dev_row, prd_row = dev_by_key[key], prd_by_key[key]
        diffs = {
            col: (dev_row.get(col), prd_row.get(col))
            for col in common_columns
            if col not in key_columns and dev_row.get(col) != prd_row.get(col)
        }
        if diffs:
            mismatched.append((key, diffs))

    return only_in_dev, only_in_prd, mismatched


def print_report(key_columns, only_in_dev, only_in_prd, mismatched):
    print("=" * 80)
    print("DEV vs PRD comparison report")
    print("=" * 80)
    print(f"Business key columns: {key_columns}")
    print(f"Rows only in DEV (would be inserted into PRD): {len(only_in_dev)}")
    for key in only_in_dev:
        print(f"  + {dict(zip(key_columns, key))}")

    print(f"\nRows only in PRD (not present in DEV staging): {len(only_in_prd)}")
    for key in only_in_prd:
        print(f"  - {dict(zip(key_columns, key))}")

    print(f"\nRows with same business key but differing values: {len(mismatched)}")
    for key, diffs in mismatched:
        print(f"  ~ {dict(zip(key_columns, key))}")
        for col, (dev_val, prd_val) in diffs.items():
            print(f"      {col}: DEV={dev_val!r}  PRD={prd_val!r}")

    print("=" * 80)
    if not only_in_dev and not only_in_prd and not mismatched:
        print("No differences found. DEV and PRD are in sync for this table/business key.")
    print("=" * 80)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config-id", type=int, help="ConfigurationId in mig.TableConfiguration (looked up on the PRD connection). Overrides --dev-schema/--dev-table/--prd-schema/--prd-table/--business-keys if set.")

    parser.add_argument("--dev-server", required=True)
    parser.add_argument("--dev-database", required=True)
    parser.add_argument("--dev-schema")
    parser.add_argument("--dev-table")
    parser.add_argument("--dev-user", default=os.environ.get("DEV_SQL_USER"))
    parser.add_argument("--dev-password", default=os.environ.get("DEV_SQL_PASSWORD"))

    parser.add_argument("--prd-server", required=True)
    parser.add_argument("--prd-database", required=True)
    parser.add_argument("--prd-schema")
    parser.add_argument("--prd-table")
    parser.add_argument("--prd-user", default=os.environ.get("PRD_SQL_USER"))
    parser.add_argument("--prd-password", default=os.environ.get("PRD_SQL_PASSWORD"))

    parser.add_argument("--business-keys", help="Comma-separated business key column names, e.g. \"Instance Name,AIC Classification\"")
    parser.add_argument("--only-in-dev", action="store_true", help="Print only the full row data for rows that exist in DEV but not in PRD, skipping the rest of the report.")

    args = parser.parse_args(argv)

    if not args.config_id and not (args.dev_schema and args.dev_table and args.prd_schema and args.prd_table and args.business_keys):
        parser.error("Either --config-id, or all of --dev-schema/--dev-table/--prd-schema/--prd-table/--business-keys, must be supplied.")

    return args


def main(argv=None):
    args = parse_args(argv)

    dev_settings = ConnectionSettings(args.dev_server, args.dev_database, args.dev_user, args.dev_password)
    prd_settings = ConnectionSettings(args.prd_server, args.prd_database, args.prd_user, args.prd_password)

    with dev_settings.connect() as dev_conn, prd_settings.connect() as prd_conn:
        if args.config_id:
            dev_schema, dev_table, prd_schema, prd_table, key_columns = load_config_from_prod(prd_conn, args.config_id)
        else:
            dev_schema, dev_table = args.dev_schema, args.dev_table
            prd_schema, prd_table = args.prd_schema, args.prd_table
            key_columns = [c.strip() for c in args.business_keys.split(",") if c.strip()]

        print(f"DEV source : {dev_schema}.{dev_table}")
        print(f"PRD target : {prd_schema}.{prd_table}")

        dev_columns, dev_rows = fetch_rows(dev_conn, dev_schema, dev_table)
        prd_columns, prd_rows = fetch_rows(prd_conn, prd_schema, prd_table)

        only_in_dev, only_in_prd, mismatched = compare(dev_columns, dev_rows, prd_columns, prd_rows, key_columns)

        if args.only_in_dev:
            dup_dev = len(dev_rows) - len({build_key(r, key_columns) for r in dev_rows})
            print(f"Duplicate business-key rows in DEV: {dup_dev}")
            print(f"Rows only in DEV (not in PRD): {len(only_in_dev)}")
            dev_by_key = {build_key(r, key_columns): r for r in dev_rows}
            for key in only_in_dev[:5]:
                print(dev_by_key[key])
            return 0

        print_report(key_columns, only_in_dev, only_in_prd, mismatched)

        return 1 if mismatched else 0


if __name__ == "__main__":
    raise SystemExit(main())
