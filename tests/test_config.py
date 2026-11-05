import re

from app import config


def test_bank_name_fits_navbar():
    assert 0 < len(config.BANK_NAME) <= 40, \
        f"BANK_NAME is {len(config.BANK_NAME)} characters; it must be 1 to 40"


def test_announcement_fits_banner():
    assert len(config.ANNOUNCEMENT) <= 120, \
        f"ANNOUNCEMENT is {len(config.ANNOUNCEMENT)} characters; the banner holds 120"


def test_brand_color_is_hex():
    assert re.fullmatch(r"#[0-9A-Fa-f]{6}", config.BRAND_COLOR), \
        f"BRAND_COLOR must be a hex colour such as #0B6E4F, got {config.BRAND_COLOR!r}"


def test_currency_is_iso_code():
    assert re.fullmatch(r"[A-Z]{3}", config.CURRENCY), \
        f"CURRENCY must be a three-letter ISO code such as USD, got {config.CURRENCY!r}"
