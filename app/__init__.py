"""DemoBank: a small banking app for the DevOps, Oracle DBA and PL/SQL course. Every customer is invented."""
import re
import subprocess
from pathlib import Path

from flask import Flask, render_template

from . import config, db

ROOT = Path(__file__).resolve().parent.parent
HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")
SYMBOLS = {"USD": "$", "EUR": "€", "GBP": "£", "NGN": "₦", "KES": "KSh ", "ZAR": "R ", "CAD": "C$", "AED": "AED "}


def read_version():
    """The commit this copy of the app was built from: VERSION is written by the pipeline."""
    version_file = ROOT / "VERSION"
    if version_file.exists():
        return version_file.read_text().strip()
    try:
        return subprocess.run(["git", "rev-parse", "--short=7", "HEAD"], cwd=ROOT, capture_output=True,
                              text=True, timeout=3, check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "dev"


def money(value):
    symbol = SYMBOLS.get(config.CURRENCY, config.CURRENCY + " ")
    return f"{symbol}{(value or 0):,.2f}"


def create_app():
    app = Flask(__name__)
    app.config["VERSION"] = read_version()

    @app.context_processor
    def bank_settings():
        return {
            "bank_name": config.BANK_NAME,
            "announcement": config.ANNOUNCEMENT,
            "brand_color": config.BRAND_COLOR if HEX_COLOR.match(config.BRAND_COLOR) else "#1A2B4A",
            "version": app.config["VERSION"],
        }

    app.add_template_filter(money, "money")

    @app.errorhandler(db.DatabaseUnavailable)
    def database_unavailable(exc):
        return render_template("error.html", title="Database unavailable", message=str(exc), code=exc.code), 503

    @app.errorhandler(404)
    def not_found(_exc):
        return render_template("error.html", title="Not found", message="There is nothing at this address."), 404

    from .routes import bp
    app.register_blueprint(bp)
    return app
