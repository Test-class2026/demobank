"""Oracle connection pool. python-oracledb in thin mode: no Oracle client install needed."""
import os
import threading

import oracledb

_pool = None
_lock = threading.Lock()


class DatabaseUnavailable(Exception):
    """The database could not be reached, or is not ready for the app yet."""

    def __init__(self, message, code=None):
        super().__init__(message)
        self.code = code


def settings():
    return {
        "user": os.environ.get("DB_USER", "demobank"),
        "password": os.environ.get("DB_PASSWORD", ""),
        "dsn": os.environ.get("DB_DSN", "localhost:1521/FREEPDB1"),
    }


def pool():
    global _pool
    with _lock:
        if _pool is None:
            _pool = oracledb.create_pool(**settings(), min=1, max=4, increment=1,
                                         tcp_connect_timeout=5, getmode=oracledb.POOL_GETMODE_TIMEDWAIT,
                                         wait_timeout=5000)
        return _pool


def _reset():
    global _pool
    with _lock:
        _pool = None


def ora_code(exc):
    err = exc.args[0] if exc.args else None
    return getattr(err, "full_code", None)


def ora_message(exc):
    err = exc.args[0] if exc.args else None
    return getattr(err, "message", str(exc))


def connection():
    try:
        return pool().acquire()
    except oracledb.Error as exc:
        _reset()
        raise DatabaseUnavailable("DemoBank cannot reach its database.", ora_code(exc)) from exc


def query(sql, **binds):
    """Run a SELECT and return the rows as dicts with lower-case keys."""
    with connection() as conn:
        with conn.cursor() as cur:
            try:
                cur.execute(sql, binds)
            except oracledb.DatabaseError as exc:
                if ora_code(exc) == "ORA-00942":
                    raise DatabaseUnavailable("The database has no DemoBank tables yet. "
                                              "Run the migrations: python scripts/migrate.py", "ORA-00942") from exc
                raise
            cols = [d[0].lower() for d in cur.description]
            return [dict(zip(cols, row)) for row in cur]


def query_one(sql, **binds):
    rows = query(sql, **binds)
    return rows[0] if rows else None


def ping():
    try:
        with connection() as conn:
            conn.ping()
        return True
    except (DatabaseUnavailable, oracledb.Error):
        return False
