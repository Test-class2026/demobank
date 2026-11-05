"""App tests that need no database: the database layer is replaced with stand-ins."""
import pytest

from app import create_app, db


@pytest.fixture
def client():
    return create_app().test_client()


def test_health_reports_database_up(client, monkeypatch):
    monkeypatch.setattr(db, "ping", lambda: True)
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json["status"] == "ok" and res.json["database"] == "up"
    assert res.json["version"]


def test_health_reports_database_down(client, monkeypatch):
    monkeypatch.setattr(db, "ping", lambda: False)
    res = client.get("/health")
    assert res.status_code == 503
    assert res.json["database"] == "down"


def test_pages_explain_a_missing_database(client, monkeypatch):
    def unavailable(*_args, **_kwargs):
        raise db.DatabaseUnavailable("DemoBank cannot reach its database.", "DPY-6005")

    monkeypatch.setattr(db, "query", unavailable)
    monkeypatch.setattr(db, "query_one", unavailable)
    res = client.get("/")
    assert res.status_code == 503
    assert b"cannot reach its database" in res.data


def test_transfer_page_renders(client):
    res = client.get("/transfer")
    assert res.status_code == 200
    assert b"bank_pkg.transfer_funds" in res.data


def test_transfer_rejects_a_bad_amount(client):
    res = client.post("/transfer", data={"from_account": "2000000001", "to_account": "2000000002", "amount": "lots"})
    assert b"Enter an amount" in res.data


def test_brand_colour_reaches_the_page(client, monkeypatch):
    from app import config
    monkeypatch.setattr(config, "BRAND_COLOR", "#0B6E4F")
    assert b"--brand: #0B6E4F" in client.get("/transfer").data


def test_announcement_is_shown(client, monkeypatch):
    from app import config
    monkeypatch.setattr(config, "ANNOUNCEMENT", "New savings rates start on Monday.")
    assert b"New savings rates start on Monday." in client.get("/transfer").data
