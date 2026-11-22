"""bank_pkg.transfer_funds against a real database. Every test rolls back, so the data never changes."""
import os
 
import oracledb
import pytest
 
from app import db
 
pytestmark = pytest.mark.skipif(not os.environ.get("RUN_DB_TESTS"), reason="needs a migrated database")
 
FROM, TO = "2000000001", "2000000002"
 
 
@pytest.fixture
def cur():
    with db.connection() as conn:
        with conn.cursor() as cursor:
            yield cursor
        conn.rollback()
 
 
def balance(cur, account):
    cur.execute("SELECT balance FROM accounts WHERE account_number = :1", [account])
    return cur.fetchone()[0]
 
 
def test_transfer_moves_money_and_records_both_sides(cur):
    before_from, before_to = balance(cur, FROM), balance(cur, TO)
    cur.callproc("bank_pkg.transfer_funds", [FROM, TO, 100, "Test transfer"])
    assert balance(cur, FROM) == before_from - 100
    assert balance(cur, TO) == before_to + 100
    cur.execute("SELECT COUNT(*) FROM transactions WHERE description = 'Test transfer'")
    assert cur.fetchone()[0] == 2
 
 
def test_insufficient_funds_changes_nothing(cur):
    before = balance(cur, FROM)
    with pytest.raises(oracledb.DatabaseError, match="ORA-20001"):
        cur.callproc("bank_pkg.transfer_funds", [FROM, TO, before + 1])
    assert balance(cur, FROM) == before
 
 
@pytest.mark.parametrize("from_acct, to_acct, amount, error", [
    (FROM, "2999999999", 10, "ORA-20002"),     # no such account
    (FROM, TO, 0, "ORA-20003"),                # amount must be positive
    (FROM, FROM, 10, "ORA-20005"),             # same account
    (FROM, TO, 60000, "ORA-20006"),            # above the transfer limit
])
def test_invalid_transfers_are_refused(cur, from_acct, to_acct, amount, error):
    with pytest.raises(oracledb.DatabaseError, match=error):
        cur.callproc("bank_pkg.transfer_funds", [from_acct, to_acct, amount])
 
 
def test_balance_changes_are_audited(cur):
    cur.execute("SELECT COUNT(*) FROM balance_audit")
    before = cur.fetchone()[0]
    cur.callproc("bank_pkg.transfer_funds", [FROM, TO, 10])
    cur.execute("SELECT COUNT(*) FROM balance_audit")
    assert cur.fetchone()[0] == before + 2