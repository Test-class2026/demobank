"""Smoke tests against a real, migrated database. The pipeline runs these with RUN_DB_TESTS=1."""
import os

import pytest

from app import create_app, db

pytestmark = pytest.mark.skipif(not os.environ.get("RUN_DB_TESTS"), reason="needs a migrated database")


@pytest.fixture
def client():
    return create_app().test_client()


def test_sample_data_is_loaded():
    counts = db.query_one("""
        SELECT (SELECT COUNT(*) FROM customers) AS customers,
               (SELECT COUNT(*) FROM accounts) AS accounts,
               (SELECT COUNT(*) FROM transactions) AS transactions FROM dual""")
    assert counts["customers"] >= 500
    assert counts["accounts"] >= 800
    assert counts["transactions"] >= 40000


def test_balances_match_transactions():
    mismatches = db.query_one("""
        SELECT COUNT(*) AS n FROM accounts a
        WHERE a.balance <> (SELECT NVL(SUM(CASE WHEN t.txn_type IN ('DEPOSIT', 'INTEREST', 'TRANSFER_IN')
                                                THEN t.amount ELSE -t.amount END), 0)
                            FROM transactions t WHERE t.account_id = a.account_id)""")
    assert mismatches["n"] == 0


@pytest.mark.parametrize("path", ["/", "/recent", "/customers", "/customers?q=ada", "/customers?kyc=PENDING",
                                  "/customers/1", "/accounts/1", "/accounts/1?page=2",
                                  "/accounts/lookup?number=2000000001", "/health"])
def test_page_loads(client, path):
    assert client.get(path).status_code == 200
