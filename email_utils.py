"""
email_utils.py — Real email verification for LA-MALIVA VISTA HOTEL.

Performs three layers of validation, far beyond a simple regex:

  1. SYNTAX      — RFC-style regex check of local@domain parts.
  2. DISPOSABLE  — blocks known throwaway/temp-mail domains (fake signups).
  3. DNS DELIVERABILITY — live DNS lookup (MX preferred, A fallback) to
     confirm the recipient domain actually exists and can receive mail.

DNS lookups use dnspython when available and gracefully fall back to a
plain socket lookup. A total network outage soft-passes (so local
development and offline demos keep working), but an authoritative
NXDOMAIN (domain really does not exist) always hard-fails.
"""

import re
import socket

try:
    import dns.resolver  # type: ignore
    import dns.exception  # type: ignore
    _HAS_DNSPYTHON = True
except Exception:  # pragma: no cover - optional dependency
    _HAS_DNSPYTHON = False

# ---------------------------------------------------------------------------
# Regex
# ---------------------------------------------------------------------------
EMAIL_REGEX = re.compile(
    r"^[A-Za-z0-9](?:[A-Za-z0-9._%+-]{0,62}[A-Za-z0-9])?"
    r"@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z]{2,63})+$"
)

# ---------------------------------------------------------------------------
# Disposable / throwaway email domains (commonly abused for fake accounts)
# ---------------------------------------------------------------------------
DISPOSABLE_DOMAINS = {
    "mailinator.com", "10minutemail.com", "guerrillamail.com", "yopmail.com",
    "tempmail.com", "temp-mail.org", "throwawaymail.com", "sharklasers.com",
    "getnada.com", "dispostable.com", "maildrop.cc", "fakeinbox.com",
    "trashmail.com", "trashmail.de", "mytemp.email", "mohmal.com",
    "emailondeck.com", "spamgourmet.com", "burnermail.io", "mailnesia.com",
    "tempr.email", "discard.email", "moakt.com", "tempmailo.com",
    "minuteinbox.com", "mail-temp.com", "emailtemporaire.com",
    "33mail.com", "anonaddy.com", "simplelogin.io", "inboxbear.com",
    "spambog.com", "mailcatch.com", "tempinbox.com", "mailexpire.com",
    "jetable.org", "mailde.de", "mailde.info", "altmails.com",
    "esanovi.com", "grr.la", "spam4.me", "1secmail.com", "1secmail.net",
    "esiix.com", "wwjmp.com", "xojxe.com", "yoggm.com", "vjuum.com",
    "laafd.com", "txcct.com", "kzccv.com", "qiott.com", "e4ward.com",
}

# Well-known free providers (flagged for analytics, NOT blocked)
FREE_PROVIDERS = {
    "gmail.com", "googlemail.com", "yahoo.com", "outlook.com", "hotmail.com",
    "live.com", "icloud.com", "aol.com", "proton.me", "protonmail.com",
    "zoho.com", "gmx.com", "yandex.com", "mail.com",
}

ROLE_PREFIXES = {
    "admin", "administrator", "support", "info", "sales", "contact",
    "help", "hello", "noreply", "no-reply", "postmaster", "webmaster",
    "hostmaster", "abuse", "billing", "office", "team",
}


# ---------------------------------------------------------------------------
# Layer checks
# ---------------------------------------------------------------------------
def validate_email_syntax(email: str) -> bool:
    """Layer 1: RFC-style syntax check."""
    email = (email or "").strip()
    if len(email) < 6 or len(email) > 254:
        return False
    return bool(EMAIL_REGEX.match(email))


def domain_has_valid_dns(domain: str) -> bool:
    """
    Layer 3: live DNS check. True when the domain publishes MX records
    (or at least resolves to an address that could accept mail).

    - NXDOMAIN              -> False  (domain does not exist: hard fail)
    - DNS library missing   -> socket fallback
    - network outage        -> True   (soft pass, never blocks signup)
    """
    if not domain:
        return False

    if _HAS_DNSPYTHON:
        try:
            answers = dns.resolver.resolve(domain, "MX")
            if answers:
                return True
        except dns.resolver.NXDOMAIN:
            # Domain genuinely does not exist -> hard fail
            return False
        except (dns.resolver.NoAnswer, dns.resolver.NoNameservers):
            # Domain exists but no MX; some domains accept via A record
            pass
        except Exception:
            # Resolver/network unavailable -> soft pass so we never lock
            # out legitimate users because of *our* connectivity.
            return True

    # Fallback / no-MX path: does the domain resolve at all?
    try:
        socket.getaddrinfo(domain, 443)
        return True
    except socket.gaierror:
        return False
    except Exception:
        return True


def is_disposable_domain(domain: str) -> bool:
    """Layer 2: throwaway/temp-mail provider check."""
    return (domain or "").lower().rstrip(".") in DISPOSABLE_DOMAINS


def is_free_provider(domain: str) -> bool:
    return (domain or "").lower().rstrip(".") in FREE_PROVIDERS


def is_role_based(email: str) -> bool:
    local = (email or "").split("@")[0].lower()
    return local in ROLE_PREFIXES


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def validate_email_real(email: str, allow_role: bool = True) -> dict:
    """
    Full real-email verification pipeline.

    Returns a dict:
        {
          "valid":        bool   -> signup may proceed
          "reason":       str    -> human-readable explanation
          "email":        str    -> normalized (lowercased, trimmed)
          "domain":       str
          "disposable":   bool
          "role_based":   bool
          "free_provider":bool
          "deliverable":  bool|None -> None when DNS was unavailable
        }
    """
    result = {
        "valid": False,
        "reason": "",
        "email": "",
        "domain": "",
        "disposable": False,
        "role_based": False,
        "free_provider": False,
        "deliverable": None,
    }

    cleaned = (email or "").strip().lower()
    result["email"] = cleaned

    if not cleaned:
        result["reason"] = "Email address is required."
        return result

    if not validate_email_syntax(cleaned):
        result["reason"] = "Invalid email format — check for typos (e.g. name@example.com)."
        return result

    domain = cleaned.split("@")[1]
    result["domain"] = domain
    result["role_based"] = is_role_based(cleaned)
    result["free_provider"] = is_free_provider(domain)

    if is_disposable_domain(domain):
        result["disposable"] = True
        result["reason"] = "Disposable/temp email addresses are not allowed — please use your real inbox."
        return result

    deliverable = domain_has_valid_dns(domain)
    result["deliverable"] = deliverable
    if not deliverable:
        result["reason"] = f"'{domain}' does not exist or cannot receive email. Please double-check the address."
        return result

    result["valid"] = True
    result["reason"] = "Verified — this address looks real and can receive mail."
    return result
