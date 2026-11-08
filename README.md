# DemoBank

A small banking application for the **DevOps, Oracle DBA and Advanced SQL** course.
Every customer, account and transaction in it is invented, and every email address is at `example.com`.

| Day | What happens to this repository |
|-----|------------------------------|
| 1 | Git, Terraform and the pipeline: change `app/config.py`, build the server, ship through GitHub Actions |
| 2 | Oracle administration on the server's database: users, roles, auditing, backup and recovery |
| 3 | SQL and PL/SQL: `bank_pkg.transfer_funds`, triggers, analytic queries, execution plans |

## What is where it is

| Path | What it is |
|------|------------|
| `app/` | Flask app: Jinja templates, Bootstrap, htmx, Alpine.js and Chart.js (all served from `app/static/vendor`, no build step) |
| `app/config.py` | The bank's name, announcement banner, brand colour and currency |
| `tests/` | `pytest` checks. `test_with_database.py` only runs when `RUN_DB_TESTS=1` |
| `db/migrations/` | `V###__name.sql`, applied in order by `scripts/migrate.py` and recorded in `SCHEMA_HISTORY` |
| `terraform/` | The EC2 server, security group and key pair |
| `deploy/` | What the pipeline runs on the server, and the systemd unit |
| `.github/workflows/pipeline.yml` | Test on every pull request; deploy after a merge to main, with approval |

## The sample data

`V002__seed_data.sql` loads 12 branches, 600 customers, about 1,000 accounts and about 60,000 transactions,
the same rows in every database because `DBMS_RANDOM` is seeded. Balances always equal credits minus debits
and never go below zero. About 7% of accounts are dormant (no activity after 2024), about 1% of deposits are
unusually large, and some customers are PENDING or REJECTED for KYC.

`transactions.account_id` deliberately has no index: Day 3 finds the full scan in an execution plan and adds it.

## Migrations

* One change per file, numbered with the next free version: `V003__add_something.sql`.
* End SQL statements with `;` at the end of a line. End PL/SQL blocks (`DECLARE`, `BEGIN`, `CREATE PACKAGE` ...)
  with a line containing only `/`.
* Never edit a migration that has been merged. The runner records each file's checksum and stops if one changes.

## Day 3 contract: transfers

The **Transfer** page calls

```sql
bank_pkg.transfer_funds(p_from_account   IN accounts.account_number%TYPE,
                        p_to_account     IN accounts.account_number%TYPE,
                        p_amount         IN NUMBER,
                        p_reference      IN VARCHAR2 DEFAULT NULL);
```

and commits if it returns. Until the package exists, the page says transfers are not switched on yet.
Raise application errors in the range `-20000` to `-20999` (for example `-20001` for insufficient funds):
the page shows their message to the user.

## Run it on your laptop

You need Docker Desktop and Python 3.12.

```powershell
# 1. A local Oracle database (first start takes a few minutes)
docker run -d --name oracle-local -p 127.0.0.1:1521:1521 -e ORACLE_PASSWORD=LocalOnly_1 `
  -e APP_USER=demobank -e APP_USER_PASSWORD=LocalOnly_1 gvenzl/oracle-free:23-slim

# 2. Python packages
python -m venv .venv
.venv\Scripts\Activate.ps1          # macOS: source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt

# 3. Point the app at the database, migrate, run
$env:DB_PASSWORD = "LocalOnly_1"     # macOS: export DB_PASSWORD=LocalOnly_1
python scripts/migrate.py
flask --app app run --debug
```

Open http://127.0.0.1:5000. Run the tests with `pytest`, or against the database with
`$env:RUN_DB_TESTS = "1"; pytest`.

## Settings the pipeline needs

| Name | Kind | Value |
|------|------|-------|
| `EC2_HOST` | Secret | The server's public IP, from `terraform output -raw public_ip` |
| `EC2_SSH_KEY` | Secret | The private deploy key, `~/.ssh/demobank_deploy` |
| `DEPLOY_ENABLED` | Variable | `true` once the server exists |
| `production` | Environment | With yourself as a required reviewer |

On the server, the database passwords are generated at first boot and kept in `/etc/demobank/`
(`oracle.env` for SYS, `demobank.env` for the app). They are never in Terraform state or in Git.
