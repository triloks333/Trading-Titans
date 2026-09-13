"""Offline syntax check for a Postgres migration.

Parses the file with libpg_query (via pglast) so top-level SQL errors are caught
without a database, then parses every PL/pgSQL function body separately, since
libpg_query treats a function body as an opaque string literal.

    python scripts/check_migration_sql.py supabase/migrations/<file>.sql
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from pglast import parse_sql
from pglast.parser import ParseError, parse_plpgsql_json as parse_plpgsql


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python scripts/check_migration_sql.py <file.sql>")

    path = Path(sys.argv[1])
    sql = path.read_text(encoding="utf-8")

    try:
        statements = parse_sql(sql)
    except ParseError as exc:
        print(f"FAIL top-level parse: {exc}")
        return 1
    print(f"OK   top-level parse: {len(statements)} statements")

    # Re-parse each CREATE FUNCTION as PL/pgSQL so the body is actually checked.
    checked = 0
    for chunk in sql.split("\n$$;"):
        if "LANGUAGE plpgsql" not in chunk:
            continue
        start = chunk.find("CREATE OR REPLACE FUNCTION")
        if start == -1:
            continue
        body = chunk[start:] + "\n$$;"
        name = body.split("(")[0].replace("CREATE OR REPLACE FUNCTION", "").strip()
        try:
            parse_plpgsql(body)
        except ParseError as exc:
            print(f"FAIL plpgsql body {name}: {exc}")
            return 1
        checked += 1
        print(f"OK   plpgsql body {name}")

    # Anonymous DO blocks are PL/pgSQL too, and libpg_query treats their body as
    # an opaque string, so check them the same way.
    do_blocks = 0
    for match in re.finditer(r"DO \$(\w+)\$(.*?)\$\1\$;", sql, re.DOTALL):
        tag, inner = match.group(1), match.group(2)
        wrapper = (
            "CREATE OR REPLACE FUNCTION __check_do() RETURNS void\n"
            f"LANGUAGE plpgsql AS $body${inner}$body$;"
        )
        try:
            parse_plpgsql(wrapper)
        except ParseError as exc:
            print(f"FAIL DO ${tag}$ block: {exc}")
            return 1
        do_blocks += 1
        print(f"OK   DO ${tag}$ block")

    print(f"\n{checked} PL/pgSQL function(s) and {do_blocks} DO block(s) parsed, no syntax errors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
