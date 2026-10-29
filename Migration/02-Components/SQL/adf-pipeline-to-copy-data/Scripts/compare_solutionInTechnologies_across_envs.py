"""
Compare `meta_solution.solutionInTechnologies` across Dev / Tst / Acc / Prd, keyed on the `name`
column (its enforced UNIQUE business key), to find out which rows Production is missing (i.e. what
Wave 3 would need to load) before building/running the actual migration pipeline.

This is a read-only sanity check: it does not modify any database. It connects directly to each
environment's own live `meta_solution.solutionInTechnologies` table - it does NOT require the
mig_stg_dev / mig_stg_tst / mig_stg_acc staging tables to exist yet (they don't yet, for this
table family), so this can be run immediately, ahead of building the Wave 3 staging/load pipeline.

Usage
-----
Using the real environment's default server FQDNs (see deploy-real-environment.ps1):

    python compare_solutionInTechnologies_across_envs.py

Override any server/database if needed:

    python compare_solutionInTechnologies_across_envs.py --prd-server myprdserver.database.windows.net

Authentication
--------------
Defaults to Azure Active Directory authentication (required for Azure SQL). The AAD token is
acquired once via azure-identity (InteractiveBrowserCredential, with MFA support) and reused for
every connection. For SQL auth instead, supply --<env>-user/--<env>-password (or set the
DEV_SQL_USER/DEV_SQL_PASSWORD, TST_SQL_USER/TST_SQL_PASSWORD, ACC_SQL_USER/ACC_SQL_PASSWORD,
PRD_SQL_USER/PRD_SQL_PASSWORD environment variables).

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

# Real environment server FQDNs (see deploy-real-environment.ps1); override via CLI if different.
DEFAULT_SERVERS = {
    "dev": "msc-ssr-dmap-dev.database.windows.net",
    "tst": "msc-ssr-dmap-tst.database.windows.net",
    "acc": "msc-ssr-dmap-acc.database.windows.net",
    "prd": "msc-ssr-dmap-prd.database.windows.net",
}
DEFAULT_DATABASE = "DMAP"
DEFAULT_SCHEMA = "meta_solution"
DEFAULT_TABLE = "solutionInTechnologies"
DEFAULT_BUSINESS_KEY = "name"


@lru_cache(maxsize=1)
def _get_aad_token_struct(auth_mode: str = "interactive") -> bytes:
    """Acquire an AAD access token once and encode it for SQL_COPT_SS_ACCESS_TOKEN.

    auth_mode="interactive" (default) pops a browser login (supports MFA) - use for normal,
    local/manual runs. auth_mode="azure-cli" reuses whatever account is already signed in via
    `az login` (no browser popup) - use for automation/headless runs.
    """
    if auth_mode == "azure-cli":
        from azure.identity import AzureCliCredential

        credential = AzureCliCredential()
    else:
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
    auth_mode: str = "interactive"

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
        token_struct = _get_aad_token_struct(self.auth_mode)
        return pyodbc.connect(self.connection_string(), attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct})


def quote_ident(name: str) -> str:
    return "[" + name.replace("]", "]]") + "]"


def fetch_business_keys(conn: pyodbc.Connection, schema: str, table: str, key_column: str) -> list[str]:
    qualified = f"{quote_ident(schema)}.{quote_ident(table)}"
    cursor = conn.cursor()
    cursor.execute(f"SELECT {quote_ident(key_column)} FROM {qualified}")
    return [row[0] for row in cursor.fetchall()]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for env in ("dev", "tst", "acc", "prd"):
        parser.add_argument(f"--{env}-server", default=DEFAULT_SERVERS[env])
        parser.add_argument(f"--{env}-database", default=DEFAULT_DATABASE)
        parser.add_argument(f"--{env}-user", default=os.environ.get(f"{env.upper()}_SQL_USER"))
        parser.add_argument(f"--{env}-password", default=os.environ.get(f"{env.upper()}_SQL_PASSWORD"))
    parser.add_argument("--schema", default=DEFAULT_SCHEMA)
    parser.add_argument("--table", default=DEFAULT_TABLE)
    parser.add_argument("--business-key", default=DEFAULT_BUSINESS_KEY)
    parser.add_argument("--auth", choices=("interactive", "azure-cli"), default="interactive",
                         help="interactive = browser login (default, supports MFA); "
                              "azure-cli = reuse the account already signed in via `az login` (no popup).")
    args = parser.parse_args(argv)

    envs = ("dev", "tst", "acc", "prd")
    keys_by_env: dict[str, list[str]] = {}

    for env in envs:
        settings = ConnectionSettings(
            server=getattr(args, f"{env}_server"),
            database=getattr(args, f"{env}_database"),
            user=getattr(args, f"{env}_user"),
            password=getattr(args, f"{env}_password"),
            auth_mode=args.auth,
        )
        print(f"Connecting to {env.upper()} ({settings.server}/{settings.database}) ...", file=sys.stderr)
        with settings.connect() as conn:
            keys_by_env[env] = fetch_business_keys(conn, args.schema, args.table, args.business_key)

    print("=" * 80)
    print(f"{args.schema}.{args.table} - comparison by [{args.business_key}] across dev/tst/acc/prd")
    print("=" * 80)

    # Flag duplicates within each environment first (name is supposed to be UNIQUE per the schema).
    any_duplicates = False
    for env in envs:
        values = keys_by_env[env]
        seen_once = set()
        dups = {v for v in values if v in seen_once or seen_once.add(v)}
        if dups:
            any_duplicates = True
            print(f"WARNING: duplicate [{args.business_key}] values in {env.upper()}: {sorted(dups)}")
    if any_duplicates:
        print("-" * 80)

    sets_by_env = {env: set(keys_by_env[env]) for env in envs}
    lower_envs = ("dev", "tst", "acc")
    union_lower = sets_by_env["dev"] | sets_by_env["tst"] | sets_by_env["acc"]

    missing_in_prd = sorted(union_lower - sets_by_env["prd"])
    only_in_prd = sorted(sets_by_env["prd"] - union_lower)

    print(f"Row counts: dev={len(sets_by_env['dev'])}  tst={len(sets_by_env['tst'])}  "
          f"acc={len(sets_by_env['acc'])}  prd={len(sets_by_env['prd'])}")
    print()
    print(f"Present in a lower environment but MISSING in Prd (need to load): {len(missing_in_prd)}")
    for name in missing_in_prd:
        present_in = [e for e in lower_envs if name in sets_by_env[e]]
        print(f"  + {name!r}  (present in: {', '.join(present_in)})")

    print()
    print(f"Present in Prd but not in any lower environment (informational only): {len(only_in_prd)}")
    for name in only_in_prd:
        print(f"  - {name!r}")

    print("=" * 80)
    if not missing_in_prd:
        print("Prd already has every name from Dev/Tst/Acc - nothing to load for this table.")
    else:
        print(f"{len(missing_in_prd)} row(s) from lower environments are missing in Production.")
    print("=" * 80)

    return 1 if missing_in_prd else 0


if __name__ == "__main__":
    raise SystemExit(main())
