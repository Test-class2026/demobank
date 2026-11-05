from decimal import Decimal, InvalidOperation

import oracledb
from flask import Blueprint, abort, current_app, jsonify, render_template, request

from . import db

bp = Blueprint("bank", __name__)
PAGE_SIZE = 25


def is_htmx():
    return request.headers.get("HX-Request") == "true"


@bp.app_template_filter("channel")
def channel_label(channel):
    return "ATM" if channel == "ATM" else (channel or "").title()


@bp.app_template_global()
def page_links(page, pages):
    """Page numbers to show: first, last, and the neighbours of the current page, with None for a gap."""
    shown = sorted({p for p in (1, page - 1, page, page + 1, pages) if 1 <= p <= pages})
    links = []
    for p in shown:
        if links and p - links[-1] > 1:
            links.append(None)
        links.append(p)
    return links


@bp.get("/health")
def health():
    up = db.ping()
    body = {"status": "ok" if up else "degraded", "database": "up" if up else "down",
            "version": current_app.config["VERSION"]}
    return jsonify(body), 200 if up else 503


@bp.get("/")
def dashboard():
    kpis = db.query_one("""
        SELECT (SELECT COUNT(*) FROM customers)                          AS customers,
               (SELECT COUNT(*) FROM accounts WHERE status = 'ACTIVE')   AS active_accounts,
               (SELECT NVL(SUM(balance), 0) FROM accounts)               AS total_balance,
               (SELECT COUNT(*) FROM transactions
                 WHERE txn_date >= (SELECT MAX(txn_date) FROM transactions) - INTERVAL '30' DAY) AS txns_30d
        FROM dual""")
    # Charts run up to the newest transaction, so the sample data always fills them
    monthly = db.query("""
        WITH latest AS (SELECT TRUNC(MAX(txn_date), 'MM') AS m FROM transactions)
        SELECT TO_CHAR(TRUNC(t.txn_date, 'MM'), 'Mon YYYY') AS month,
               SUM(CASE WHEN t.txn_type IN ('DEPOSIT', 'INTEREST', 'TRANSFER_IN') THEN t.amount ELSE 0 END) AS money_in,
               SUM(CASE WHEN t.txn_type IN ('WITHDRAWAL', 'FEE', 'TRANSFER_OUT') THEN t.amount ELSE 0 END) AS money_out
        FROM   transactions t CROSS JOIN latest
        WHERE  t.txn_date >= ADD_MONTHS(latest.m, -11)
        GROUP  BY TRUNC(t.txn_date, 'MM')
        ORDER  BY TRUNC(t.txn_date, 'MM')""")
    branches = db.query("""
        SELECT b.branch_name, NVL(SUM(a.balance), 0) AS balance
        FROM   branches b LEFT JOIN accounts a ON a.branch_code = b.branch_code
        GROUP  BY b.branch_name
        ORDER  BY balance DESC""")
    channels = db.query("""
        SELECT NVL(channel, 'UNKNOWN') AS channel, COUNT(*) AS txns
        FROM   transactions
        GROUP  BY channel
        ORDER  BY txns DESC""")
    charts = {
        "monthly": {"labels": [r["month"] for r in monthly],
                    "money_in": [float(r["money_in"]) for r in monthly],
                    "money_out": [float(r["money_out"]) for r in monthly]},
        "branches": {"labels": [r["branch_name"] for r in branches],
                     "values": [float(r["balance"]) for r in branches]},
        "channels": {"labels": [channel_label(r["channel"]) for r in channels],
                     "values": [int(r["txns"]) for r in channels]},
    }
    return render_template("dashboard.html", kpis=kpis, charts=charts, recent=recent_transactions())


@bp.get("/recent")
def recent():
    return render_template("_recent.html", recent=recent_transactions())


def recent_transactions():
    return db.query("""
        SELECT t.txn_date, t.txn_type, t.amount, t.channel, t.description,
               a.account_id, a.account_number, c.full_name
        FROM   transactions t
        JOIN   accounts  a ON a.account_id  = t.account_id
        JOIN   customers c ON c.customer_id = a.customer_id
        ORDER  BY t.txn_date DESC, t.txn_id DESC
        FETCH FIRST 10 ROWS ONLY""")


@bp.get("/customers")
def customers():
    q = request.args.get("q", "").strip() or None
    kyc = request.args.get("kyc") or None
    page = max(request.args.get("page", 1, type=int), 1)
    rows = db.query("""
        SELECT c.customer_id, c.full_name, c.email, c.city, c.kyc_status,
               COUNT(a.account_id)      AS accounts,
               NVL(SUM(a.balance), 0)   AS total_balance,
               COUNT(*) OVER ()         AS total_rows
        FROM   customers c LEFT JOIN accounts a ON a.customer_id = c.customer_id
        WHERE  (:q IS NULL OR UPPER(c.full_name) LIKE '%' || UPPER(:q) || '%'
                           OR UPPER(c.email)     LIKE '%' || UPPER(:q) || '%')
          AND  (:kyc IS NULL OR c.kyc_status = :kyc)
        GROUP  BY c.customer_id, c.full_name, c.email, c.city, c.kyc_status
        ORDER  BY c.full_name, c.customer_id
        OFFSET :offset ROWS FETCH NEXT :page_size ROWS ONLY""",
                    q=q, kyc=kyc, offset=(page - 1) * PAGE_SIZE, page_size=PAGE_SIZE)
    total = rows[0]["total_rows"] if rows else 0
    pages = max((total + PAGE_SIZE - 1) // PAGE_SIZE, 1)
    context = dict(rows=rows, total=total, page=page, pages=pages, q=q or "", kyc=kyc or "")
    return render_template("_customer_rows.html" if is_htmx() else "customers.html", **context)


@bp.get("/customers/<int:customer_id>")
def customer(customer_id):
    person = db.query_one("SELECT * FROM customers WHERE customer_id = :id", id=customer_id) or abort(404)
    accounts = db.query("""
        SELECT a.*, b.branch_name
        FROM   accounts a JOIN branches b ON b.branch_code = a.branch_code
        WHERE  a.customer_id = :id
        ORDER  BY a.opened_on""", id=customer_id)
    return render_template("customer.html", person=person, accounts=accounts)


@bp.get("/accounts/<int:account_id>")
def account(account_id):
    acct = db.query_one("""
        SELECT a.*, b.branch_name, c.full_name, c.customer_id
        FROM   accounts a
        JOIN   branches  b ON b.branch_code = a.branch_code
        JOIN   customers c ON c.customer_id = a.customer_id
        WHERE  a.account_id = :id""", id=account_id) or abort(404)
    page = max(request.args.get("page", 1, type=int), 1)
    txns = db.query("""
        SELECT txn_id, txn_date, txn_type, amount, description, channel
        FROM   transactions
        WHERE  account_id = :id
        ORDER  BY txn_date DESC, txn_id DESC
        OFFSET :offset ROWS FETCH NEXT :page_size ROWS ONLY""",
                    id=account_id, offset=(page - 1) * PAGE_SIZE, page_size=PAGE_SIZE + 1)
    context = dict(acct=acct, txns=txns[:PAGE_SIZE], page=page, more=len(txns) > PAGE_SIZE)
    return render_template("_statement_rows.html" if is_htmx() else "account.html", **context)


@bp.get("/accounts/lookup")
def account_lookup():
    number = request.args.get("number", "").strip()
    acct = None
    if number:
        acct = db.query_one("""
            SELECT a.account_number, a.account_type, a.balance, a.status, c.full_name
            FROM   accounts a JOIN customers c ON c.customer_id = a.customer_id
            WHERE  a.account_number = :num""", num=number)
    return render_template("_lookup.html", acct=acct, number=number)


@bp.get("/transfer")
def transfer_form():
    return render_template("transfer.html")


@bp.post("/transfer")
def transfer():
    from_acct = request.form.get("from_account", "").strip()
    to_acct = request.form.get("to_account", "").strip()
    reference = request.form.get("reference", "").strip()[:100] or None
    try:
        amount = Decimal(request.form.get("amount", ""))
    except InvalidOperation:
        return render_template("_transfer_result.html", ok=False, message="Enter an amount, such as 250.00.")

    # The rules live in the database: bank_pkg.transfer_funds is written on Day 3
    try:
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.callproc("bank_pkg.transfer_funds", [from_acct, to_acct, amount, reference])
            conn.commit()
    except oracledb.DatabaseError as exc:
        code, message = db.ora_code(exc), db.ora_message(exc)
        if code == "ORA-06550" and "PLS-00201" in message:
            message = ("Transfers are not switched on yet. The database has no bank_pkg.transfer_funds "
                       "procedure: you write it on Day 3.")
        elif code and "ORA-20000" <= code <= "ORA-20999":
            message = message.split(":", 1)[-1].split("\n")[0].strip()
        else:
            message = f"The database refused the transfer ({code}): {message.splitlines()[0]}"
        return render_template("_transfer_result.html", ok=False, message=message, code=code)

    return render_template("_transfer_result.html", ok=True, amount=amount, from_acct=from_acct, to_acct=to_acct)
