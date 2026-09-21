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

EMAIL_BODY = """\
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
        <h2 style="color:#0a2a66;font-size:18px;margin:0 0 12px;">Verify your email address</h2>
        <p style="color:#4a5568;font-size:14px;line-height:1.7;margin:0 0 24px;">
          Welcome to La-Maliva Vista Hotel! Please confirm this email address to activate
          your account. The link below is valid for <strong>24 hours</strong>.
        </p>
        <div style="text-align:center;margin:0 0 24px;">
          <a href="{verify_url}"
             style="display:inline-block;background:linear-gradient(115deg,#ffc94d,#ff9d2e);color:#06122b;
                    font-weight:700;font-size:14px;letter-spacing:1px;text-decoration:none;
                    padding:14px 34px;border-radius:12px;">
             Verify My Email
          </a>
        </div>
        <p style="color:#8892a6;font-size:12px;line-height:1.6;margin:0 0 8px;">
          Or paste this link into your browser:<br>
          <span style="color:#123a8f;word-break:break-all;">{verify_url}</span>
        </p>
        <p style="color:#8892a6;font-size:12px;line-height:1.6;margin:0;">
          Didn't create an account? You can safely ignore this email.
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
    msg.attach(MIMEText("Please open this email in an HTML-capable client to verify your address.", "plain"))
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
    """Send the branded address-verification email."""
    return send_email(to, "Verify your email — La-Maliva Vista Hotel", EMAIL_BODY.format(verify_url=verify_url))


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
    """Send the branded password-reset email."""
    return send_email(to, "Reset your password — La-Maliva Vista Hotel", RESET_BODY.format(reset_url=reset_url))
