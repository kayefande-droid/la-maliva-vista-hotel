"""
mailer.py — Transactional email for LA-MALIVA VISTA HOTEL.

Configuration (environment variables on Render/Railway):
    SMTP_HOST       e.g. smtp.gmail.com
    SMTP_PORT       587 (TLS, default) or 465 (SSL)
    SMTP_USER       mailbox username
    SMTP_PASSWORD   mailbox password / app password
    MAIL_FROM       display sender, e.g. "La-Maliva Vista <noreply@lamaliva.com>"

If SMTP is not configured, send_email() returns False and the caller
falls back to logging the link (useful for local development).
"""

import os
import re
import logging
import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

logger = logging.getLogger(__name__)

SITE_BASE = "https://la-maliva-vista-hotel.onrender.com"
LOGO_URL = f"{SITE_BASE}/static/icons/icon-192.png"
LOGO_MAPS_URL = "https://maps.google.com/maps/api/staticmap?center=La+Maliva+Vista+Hotel,+Buea,+Cameroon&zoom=15&size=48x48&markers=size:tiny%7Ccolor:red%7CLa+Maliva+Vista+Hotel,+Buea,+Cameroon"


# ---------------------------------------------------------------------------
# Shared brand chrome — matches the website/app luxury design language:
# deep navy canvas, gold frame, Cormorant-style serif headline, orange CTA.
# ---------------------------------------------------------------------------
_SHELL = """\\
<!DOCTYPE html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0a1628;font-family:'Segoe UI',Arial,sans-serif;">
  <!-- preheader: invisible preview text -->
  <div style="display:none;max-height:0;overflow:hidden;">{preheader}</div>
  <div style="display:none;font-size:1px;color:#0a1628;">LA&#8209;MALIVA VISTA</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0a1628;padding:28px 12px;">
    <tr><td align="center">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">
        <tr><td style="padding:0 0 14px;" align="center">
          <img src="{logo}" width="84" height="84" alt="La-Maliva Vista" style="display:block;border-radius:50%;border:3px solid #eec37a;box-shadow:0 8px 28px rgba(0,0,0,0.45);"
               onerror="this.style.display='none'">
        </td></tr>
        <tr><td align="center" style="padding:0 0 4px;">
          <span style="color:#eec37a;font-size:13px;letter-spacing:6px;font-weight:600;">LA&#8209;MALIVA VISTA</span>
        </td></tr>
        <tr><td align="center" style="padding:0 0 22px;">
          <span style="color:rgba(253,250,244,0.55);font-size:9px;letter-spacing:5px;">A&nbsp;TASTE&nbsp;OF&nbsp;PARADISE</span>
        </td></tr>
        <tr><td style="background:linear-gradient(135deg,#12305e,#0f2240);border-radius:20px;border:1px solid rgba(238,195,122,0.35);overflow:hidden;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr><td height="4" style="background:linear-gradient(90deg,#f08c2e,#ffc94d,#f08c2e);font-size:0;line-height:0;">&nbsp;</td></tr>
            <tr><td style="padding:34px 36px 30px;">
              {content}
            </td></tr>
            <tr><td style="padding:0 36px 34px;">
              <div style="height:1px;background:rgba(238,195,122,0.25);margin:0 0 18px;"></div>
              <div style="font-size:10px;color:#4a6283;letter-spacing:2px;">
                LA-MALIVA VISTA HOTEL &middot; <a href="https://maps.app.goo.gl/EMm95NsWc5sQCM6QA" style="color:#7a8cbd;text-decoration:none;">View on Google Maps</a>
              </div>
            </td></tr>
          </table>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
"""

VERIFY_BODY_TMPL = """
  <p style="margin:0 0 22px;color:rgba(253,250,244,0.80);font-size:14px;line-height:1.6;">
    Almost there — one tap and your account is active. Use the button below to
    confirm this is really <b>{to}</b>.
  </p>
  <div style="text-align:center;margin:0 0 26px;">
    <a href="{cta_url}" style="display:inline-block;background:#eec37a;border-radius:10px;padding:15px 34px;text-decoration:none;color:#0a1628;font-weight:700;font-size:16px;letter-spacing:1px;box-shadow:0 8px 22px rgba(238,195,122,0.40);">
      Verify My Email
    </a>
  </div>
  <p style="margin:0 0 0;color:rgba(253,250,244,0.55);font-size:12px;line-height:1.55;">
    If the button doesn't work, paste this link into your browser:<br>
    <a href="{cta_url}" style="color:#ffc94d;text-decoration:none;">{cta_url}</a>
  </p>
"""

VERIFY_FOOT = """Didn't request this? You can safely ignore this email — nobody else
      can activate it without access to this inbox."""


def _brand_html(preheader, heading, body_html, cta_label, cta_url, footnote):
    return _SHELL.format(
        logo=LOGO_URL,
        logo_maps=LOGO_MAPS_URL,
        preheader=preheader,
        content=(
            f'<p style="margin:0 0 6px 0;color:#eec37a;font-size:20px;letter-spacing:1px;">{heading}</p>'
            f'{body_html}'
            f'<div style="margin-top:24px;padding-top:18px;border-top:1px solid rgba(238,195,122,0.20);">'
            f'<p style="margin:0;color:rgba(253,250,244,0.65);font-size:12px;line-height:1.5;">{footnote}</p>'
            f'</div>'
        ),
    )


def _smtp_config():
    host = os.environ.get("SMTP_HOST", "").strip()
    if not host:
        return None
    return {
        "host": host,
        "port": int(os.environ.get("SMTP_PORT", "587")),
        "user": os.environ.get("SMTP_USER", ""),
        "password": os.environ.get("SMTP_PASSWORD", ""),
        "from": (os.environ.get("MAIL_FROM") or os.environ.get("SMTP_USER") or "no-reply@lamaliva.com").strip(),
    }


def smtp_configured():
    return _smtp_config() is not None


def send_email(to, subject, html):
    """Send an HTML email. Returns True on success, False otherwise (never raises).

    Note: sending exactly the same content to the same address in a tight loop
    (e.g. a broken front-end re-clicking 'resend' many times) will fail once
    Gmail flags it as suspect. In that case the next send attempt should use a
    slightly different body or a fresh token so Gmail's spam logic sees a new
    message, not a duplicate.
    """
    cfg = _smtp_config()
    if not cfg:
        logger.warning("SMTP not configured (set SMTP_HOST/SMTP_USER/SMTP_PASSWORD) — cannot send '%s' to %s", subject, to)
        return False

    to = (to or "").strip().lower()
    if not to or not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", to):
        logger.error("Refusing to send email to invalid address: %r", to)
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = cfg["from"]
    msg["To"] = to
    msg.attach(MIMEText("Open this email in an HTML-capable client to see the La-Maliva Vista message.", "plain"))
    msg.attach(MIMEText(html, "html"))

    try:
        if cfg["port"] == 465:
            with smtplib.SMTP_SSL(cfg["host"], cfg["port"], context=ssl.create_default_context(), timeout=20) as server:
                server.login(cfg["user"], cfg["password"])
                server.sendmail(cfg["from"], [to], msg.as_string())
        else:
            with smtplib.SMTP(cfg["host"], cfg["port"], timeout=20) as server:
                server.ehlo()
                server.starttls(context=ssl.create_default_context())
                server.login(cfg["user"], cfg["password"])
                server.sendmail(cfg["from"], [to], msg.as_string())
        logger.info("Verification email sent to %s (From: %s)", to, cfg["from"])
        return True
    except Exception:
        logger.exception("Failed to send email to %s", to)
        return False


RESET_BODY = """\
  <p style="margin:0 0 22px;color:rgba(253,250,244,0.80);font-size:14px;line-height:1.6;">
    Someone (or you) asked to reset the password for <b>{to}</b>.
    Use the button below to set a new one.
  </p>
  <div style="text-align:center;margin:0 0 26px;">
    <a href="{cta_url}" style="display:inline-block;background:#eec37a;border-radius:10px;padding:15px 34px;text-decoration:none;color:#0a1628;font-weight:700;font-size:16px;letter-spacing:1px;box-shadow:0 8px 22px rgba(238,195,122,0.40);">
      Reset My Password
    </a>
  </div>
  <p style="margin:0 0 0;color:rgba(253,250,244,0.55);font-size:12px;line-height:1.55;">
    If the button doesn't work, paste this link into your browser:<br>
    <a href="{cta_url}" style="color:#ffc94d;text-decoration:none;">{cta_url}</a>
  </p>
"""

RESET_FOOT = """Didn't request this? You can safely ignore this email — your password
      is unchanged. This link expires in one hour."""


def send_password_reset_email(to, reset_url):
    """Branded password-reset email, same shell as verification."""
    html = _brand_html(
        preheader="Reset your password for La-Maliva Vista.",
        heading="Reset your password",
        body_html=RESET_BODY,
        cta_label="Reset My Password",
        cta_url=reset_url,
        footnote=RESET_FOOT,
    )
    return send_email(to, "Reset your password — La-Maliva Vista Hotel", html)


def send_verification_email(to, verify_url):
    """Branded address-verification email on the navy/gold luxury shell."""
    html = _brand_html(
        preheader="Confirm your email to activate your La-Maliva Vista account.",
        heading="Confirm your email",
        body_html=VERIFY_BODY_TMPL,
        cta_label="Verify My Email",
        cta_url=verify_url,
        footnote=VERIFY_FOOT,
    )
    return send_email(to, "Confirm your email — La-Maliva Vista Hotel", html)
