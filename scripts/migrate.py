"""Apply db/migrations/V###__name.sql in order, once each, and record them in SCHEMA_HISTORY.

Connection settings come from DB_USER, DB_PASSWORD and DB_DSN, the same variables the app uses.

Rules for migration files:
  * a SQL statement ends with ; at the end of a line
  * a PL/SQL block (DECLARE, BEGIN, CREATE PACKAGE / PROCEDURE / FUNCTION / TRIGGER / TYPE) ends with
    a line containing only /
  * a migration that has been applied is never edited: its checksum is recorded, and a changed file
    stops the run. Fix forward with a new migration instead.
"""
import hashlib
import os
import re
import sys
import time
from pathlib import Path

import oracledb

MIGRATIONS = Path(__file__).resolve().parent.parent / "db" / "migrations"
FILENAME = re.compile(r"^V(\d{3,})__\w+\.sql$")
PLSQL_START = re.compile(r"^\s*(DECLARE|BEGIN|CREATE\s+(OR\s+REPLACE\s+)?((NON)?EDITIONABLE\s+)?"
                         r"(PACKAGE|PROCEDURE|FUNCTION|TRIGGER|TYPE))\b", re.IGNORECASE)

HISTORY_DDL = """
CREATE TABLE IF NOT EXISTS schema_history (
    version     NUMBER         PRIMARY KEY,
    script      VARCHAR2(200)  NOT NULL,
    checksum    VARCHAR2(64)   NOT NULL,
    applied_at  TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL
)"""


def split_statements(text):
    """Split a migration into statements, following the rules in the module docstring."""
    statements, buf, in_plsql = [], [], False
    for line in text.splitlines():
        stripped = line.strip()
        if not buf and (not stripped or stripped.startswith("--")):
            continue
        if not buf:
            in_plsql = bool(PLSQL_START.match(line))
        if in_plsql:
            if stripped == "/":
                statements.append("\n".join(buf).strip())
                buf, in_plsql = [], False
            else:
                buf.append(line)
        else:
            buf.append(line)
            if stripped.endswith(";"):
                statements.append("\n".join(buf).strip().rstrip(";").strip())
                buf = []
    if "".join(buf).strip():
        raise SystemExit("The last statement is not terminated: end it with ; (SQL) or a / line (PL/SQL).")
    return statements


def checksum(text):
    return hashlib.sha256(text.replace("\r\n", "\n").encode()).hexdigest()


def connect(retries=60, delay=10):
    """The database may still be starting (first boot, CI service), so keep trying for a while."""
    params = dict(user=os.environ.get("DB_USER", "demobank"), password=os.environ.get("DB_PASSWORD", ""),
                  dsn=os.environ.get("DB_DSN", "localhost:1521/FREEPDB1"))
    for attempt in range(1, retries + 1):
        try:
            return oracledb.connect(**params, tcp_connect_timeout=5)
        except oracledb.Error as exc:
            if attempt == retries:
                raise
            print(f"Database not ready ({exc.args[0].full_code}), retrying in {delay}s [{attempt}/{retries}]")
            time.sleep(delay)


def main():
    files = sorted((f for f in MIGRATIONS.glob("*.sql") if FILENAME.match(f.name)),
                   key=lambda f: int(FILENAME.match(f.name).group(1)))
    versions = [int(FILENAME.match(f.name).group(1)) for f in files]
    if len(versions) != len(set(versions)):
        raise SystemExit("Two migrations share a version number. Give the newer one the next free number.")

    conn = connect()
    cur = conn.cursor()
    cur.execute(HISTORY_DDL)
    cur.execute("SELECT version, script, checksum FROM schema_history")
    applied = {v: (s, c) for v, s, c in cur}

    pending = 0
    for f, version in zip(files, versions):
        text = f.read_text(encoding="utf-8")
        if version in applied:
            script, recorded = applied[version]
            if recorded != checksum(text):
                raise SystemExit(f"{f.name} has changed since it was applied as {script}. A migration that has "
                                 "run is never edited: put the change in a new migration.")
            continue
        pending += 1
        print(f"Applying {f.name}")
        for statement in split_statements(text):
            try:
                cur.execute(statement)
            except oracledb.DatabaseError as exc:
                conn.rollback()
                first_line = statement.splitlines()[0][:80]
                print(f"FAILED in {f.name}, at: {first_line}\n{exc.args[0].message}", file=sys.stderr)
                raise SystemExit(1)
        cur.execute("INSERT INTO schema_history (version, script, checksum) VALUES (:1, :2, :3)",
                    [version, f.name, checksum(text)])
        conn.commit()

    print(f"{pending} migration(s) applied; database is at version {max(versions, default=0)}.")


if __name__ == "__main__":
    main()
