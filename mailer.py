"""
mailer.py — Transactional email for LA-MALIVA VISTA HOTEL.

Configuration (environment variables on Render/Railway):
    SMTP_HOST       e.g. smtp.gmail.com
    SMTP_PORT       587 (TLS, default) or 465 (SSL)
    SMTP_USER       mailbox username
    SMTP_PASSWORD   mailbox password / app password
    MAIL_FROM       display sender, e.g. "La-Maliva Vista <no-reply@lamaliva.com>"

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

# ---------------------------------------------------------------------------
# Shared brand chrome — matches the website/app luxury design language:
# deep navy canvas, gold frame, Cormorant-style serif headline, orange CTA.
# ---------------------------------------------------------------------------
_SHELL = """\
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
              <p style="color:rgba(253,250,244,0.45);font-size:11px;line-height:1.7;margin:0;text-align:center;">
                Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon<br>
                (+237) 679-915-967 &middot;
                <a href="{site}" style="color:#eec37a;text-decoration:none;">la-maliva-vista-hotel.onrender.com</a>
              </p>
            </td></tr>
          </table>
        </td></tr>
        <tr><td align="center" style="padding:16px 0 0;">
          <span style="color:rgba(253,250,244,0.35);font-size:10px;letter-spacing:3px;">BUEA &middot; CAMEROON &middot; MOUNTAIN SIDE</span>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
"""


def _brand_html(preheader: str, heading: str, body_html: str, cta_label: str, cta_url: str, footnote: str = "") -> str:
    """Assemble a branded email on the shared navy/gold shell."""
    cta = f'''
    <table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:6px auto 0;">
      <tr><td style="border-radius:14px;background:linear-gradient(115deg,#ffc94d,#f08c2e);">
        <a href="{cta_url}" style="display:inline-block;padding:15px 40px;color:#06122b;
           font-weight:700;font-size:14px;letter-spacing:1px;text-decoration:none;border-radius:14px;">
          {cta_label}
        </a>
      </td></tr>
    </table>'''
    foot = f'<p style="color:rgba(253,250,244,0.45);font-size:11.5px;line-height:1.7;margin:18px 0 0;text-align:center;">{footnote}</p>' if footnote else ''
    content = f'''
      <h2 style="color:#fdfaf4;font-size:24px;font-weight:600;margin:0 0 14px;text-align:center;font-family:Georgia,'Times New Roman',serif;letter-spacing:0.5px;">{heading}</h2>
      <div style="height:1px;background:rgba(240,140,46,0.5);width:64px;margin:0 auto 20px;"></div>
      <div style="color:rgba(253,250,244,0.82);font-size:14.5px;line-height:1.85;text-align:center;">{body_html}</div>
      {cta}
      {foot}
    '''
    return _SHELL.format(preheader=preheader, logo=LOGO_URL, site=SITE_BASE, content=content)


VERIFY_BODY_TMPL = """\
Welcome to <b style="color:#fdfaf4;">La&#8209;Maliva Vista Hotel</b> — the mountain's
finest address in Buea. One quick confirmation and your account is fully
active for booking rooms, viewing receipts and receiving hotel news.

<div style="margin:18px auto 0;padding:14px 18px;background:rgba(240,140,46,0.10);border:1px solid rgba(240,140,46,0.35);border-radius:12px;max-width:380px;">
  <span style="color:#eec37a;font-size:12px;letter-spacing:1px;">&#9203;&nbsp;YOUR LINK EXPIRES IN 24 HOURS</span>
</div>
"""

VERIFY_FOOT = """Didn't create this account? You can safely ignore this email — the address will never be activated without your click."""


RESET_BODY_TMPL = """\
We received a request to reset the password for your
<b style="color:#fdfaf4;">La&#8209;Maliva Vista</b> account. Tap below to choose
a new one and you're back in — your next stay is waiting.

<div style="margin:18px auto 0;padding:14px 18px;background:rgba(240,140,46,0.10);border:1px solid rgba(240,140,46,0.35);border-radius:12px;max-width:380px;">
  <span style="color:#eec37a;font-size:12px;letter-spacing:1px;">&#128274;&nbsp;SINGLE-USE &middot; EXPIRES IN 1 HOUR</span>
</div>
"""

RESET_FOOT = """Didn't request a reset? Your password is untouched — you can safely ignore this email."""


def _smtp_config():
    host = os.environ.get("SMTP_HOST", "").strip()
    if not host:
        return None
    return {
        "host": host,
        "port": int(os.environ.get("SMTP_PORT", "587")),
        "user": os.environ.get("SMTP_USER", ""),
        "password": os.environ.get("SMTP_PASSWORD", ""),
        "from": os.environ.get("MAIL_FROM") or os.environ.get("SMTP_USER", "no-reply@lamaliva.com"),
    }


def smtp_configured():
    return _smtp_config() is not None


def send_email(to, subject, html):
    """Send an HTML email. Returns True on success, False otherwise (never raises)."""
    cfg = _smtp_config()
    if not cfg:
        logger.warning("SMTP not configured (set SMTP_HOST/SMTP_USER/SMTP_PASSWORD) — cannot send '%s' to %s", subject, to)
        return False

    to = (to or "").strip()
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
        logger.info("Verification email sent to %s", to)
        return True
    except Exception:
        logger.exception("Failed to send email to %s", to)
        return False


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


RESET_BODY = """\
<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:560px;margin:0 auto;padding:32px 20px;">
    <div style="background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 6px 24px rgba(10,30,60,0.12);">
      <div style="background:linear-gradient(135deg,#0a2a66,#123a8f);padding:28px 32px;text-align:center;">
        <h1 style="color:#ffc94d;font-size:20px;letter-spacing:2px;margin:0;">LA-MALIVA VISTA</h1>
        <p style="color:rgba(255,255,255,0.75);font-size:12px;letter-spacing:3px;margin:6px 0 0;">A TASTE OF PARADISE</p>
      </div>
      <div style="padding:32px;">
        <h2 style="color:#0a2a66;font-size:18px;margin:0 0 12px;">Reset your password</h2>
        <p style="color:#4a5568;font-size:14px;line-height:1.7;margin:0 0 24px;">
          We received a request to reset the password for your La-Maliva Vista account.
          The link below is valid for <strong>1 hour</strong> and can be used once.
        </p>
        <div style="text-align:center;margin:0 0 24px;">
          <a href="{reset_url}"
             style="display:inline-block;background:linear-gradient(115deg,#ffc94d,#ff9d2e);color:#06122b;
                    font-weight:700;font-size:14px;letter-spacing:1px;text-decoration:none;
                    padding:14px 34px;border-radius:12px;">
             Choose a New Password
          </a>
        </div>
        <p style="color:#8892a6;font-size:12px;line-height:1.6;margin:0 0 8px;">
          Or paste this link into your browser:<br>
          <span style="color:#123a8f;word-break:break-all;">{reset_url}</span>
        </p>
        <p style="color:#8892a6;font-size:12px;line-height:1.6;margin:0;">
          Didn't request this? Your password is untouched — you can safely ignore this email.
        </p>
      </div>
      <div style="background:#f4f6fb;padding:18px 32px;text-align:center;">
        <p style="color:#8892a6;font-size:11px;margin:0;">
          Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon<br>
          (+237) 679-915-967 &middot; La-Maliva Vista Hotel
        </p>
      </div>
    </div>
  </div>
</body>
</html>
"""


def send_password_reset_email(to, reset_url):
    """Branded password-reset email on the navy/gold luxury shell."""
    html = _brand_html(
        preheader="Choose a new password for your La-Maliva Vista account.",
        heading="Reset your password",
        body_html=RESET_BODY_TMPL,
        cta_label="Choose a New Password",
        cta_url=reset_url,
        footnote=RESET_FOOT,
    )
    return send_email(to, "Reset your password — La-Maliva Vista Hotel", html)
