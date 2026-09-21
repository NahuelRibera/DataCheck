"""Shared parsing helpers for legacy HR salary and date formats.

Used by both the synthetic data generator (to inject realistic format
variants) and the preflight profiler (to normalize them). Kept dependency
free and in the standard library on purpose -- this is the kind of small,
auditable utility a support engineer should be able to read start to finish.
"""
from __future__ import annotations

import re
from datetime import datetime

KNOWN_DATE_FORMATS = ["%Y-%m-%d", "%m/%d/%Y", "%d-%m-%Y"]

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_CURRENCY_SYMBOLS = "€$£"


class ParseError(ValueError):
    """Raised when a value cannot be safely parsed or normalized."""


def is_valid_email(value: str) -> bool:
    return bool(_EMAIL_RE.match(value))


def parse_date(raw: str) -> tuple[str, bool]:
    """Return (iso_date, was_normalized). Raises ParseError if unparseable."""
    value = raw.strip()
    if not value:
        raise ParseError("blank date")

    for index, fmt in enumerate(KNOWN_DATE_FORMATS):
        try:
            parsed = datetime.strptime(value, fmt)
        except ValueError:
            continue
        iso = parsed.strftime("%Y-%m-%d")
        return iso, index != 0

    raise ParseError("unrecognized date format")


def parse_salary_to_cents(raw: str) -> tuple[int, bool]:
    """Return (cents, was_normalized). Raises ParseError if unparseable.

    Handles: "32500.50", "32,500.50" (US thousands), "32500,50" (EU decimal
    comma), and currency-prefixed values like "€42,000".
    """
    value = raw.strip()
    if not value:
        raise ParseError("blank salary")

    normalized = False
    if value[0] in _CURRENCY_SYMBOLS:
        value = value[1:].strip()
        normalized = True

    if not re.match(r"^-?[0-9][0-9,.\s]*$", value):
        raise ParseError("non-numeric salary")

    has_comma = "," in value
    has_dot = "." in value

    if has_comma and has_dot:
        # US-style thousands separator with a decimal point: 32,500.50
        cleaned = value.replace(",", "")
        normalized = True
    elif has_comma and not has_dot:
        tail = value.split(",")[-1]
        if len(tail) == 2:
            # European decimal comma: 32500,50
            cleaned = value.replace(",", ".")
        else:
            # Thousands-only comma: 42,000
            cleaned = value.replace(",", "")
        normalized = True
    else:
        cleaned = value

    try:
        amount = float(cleaned)
    except ValueError as error:
        raise ParseError("could not convert to a number") from error

    if amount < 0:
        raise ParseError("negative salary")

    cents = round(amount * 100)
    return cents, normalized
