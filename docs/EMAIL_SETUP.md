# Email delivery setup (Gmail SMTP on Render)

The website and app send two kinds of email:

- **Password reset** — "Forgot password?" on the sign-in page
- **Address verification** — reserved for when the email gate is enabled

Delivery is handled by `mailer.py`, which reads five **environment variables**.
This guide wires them on Render in ~5 minutes.

## One-time: create the Gmail App Password

Google blocks your normal Gmail password over SMTP — you must create a
dedicated **App Password**. Sign in as `lamalivav@gmail.com`, then:

1. Go to <https://myaccount.google.com/security>
2. Under "How you sign in to Google", enable **2-Step Verification**
   (required before App Passwords become available).
3. Once 2-Step Verification is on, open
   <https://myaccount.google.com/apppasswords>
4. App name: `La-Maliva Render` → **Create**
5. Google shows a **16-character password** like `abcd efgh ijkl mnop`.
   Copy it — you will not see it again.

> ⚠️ Never put your normal Gmail password in Render. Only the 16-character
> App Password works, and it can be revoked anytime from the same page.

## Add the environment variables on Render

1. Open <https://dashboard.render.com> → your **la-maliva-vista-hotel**
   service → **Environment** (left sidebar).
2. Add these five variables:

   | Key | Value |
   |---|---|
   | `SMTP_HOST` | `smtp.gmail.com` |
   | `SMTP_PORT` | `587` |
   | `SMTP_USER` | `lamalivav@gmail.com` |
   | `SMTP_PASSWORD` | the 16-character App Password (spaces optional) |
   | `MAIL_FROM` | `La-Maliva Vista <lamalivav@gmail.com>` |

3. Click **Save changes** — Render redeploys automatically (~2 minutes).

## Verify it works

1. Open `https://la-maliva-vista-hotel.onrender.com/api/health`
   — the JSON should now show `"email": "configured"`.
2. On the site, use **Forgot password?** with a real account
   → the branded reset email should arrive within a minute
   (check spam the first time).

If `email` still reads `not-configured` after the redeploy, a variable name
has a typo — the names are case-sensitive.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Username and Password not accepted` in logs | The App Password was copied with a typo, or 2-Step Verification is off. Regenerate it. |
| `Application-specific password required` | A normal password was used instead of the App Password. |
| Email lands in spam | Normal for a fresh sender. Mark "Not spam" once; deliverability improves. |
| Daily limit errors | Gmail caps ~500 emails/day — plenty for resets; contact reception volume stays in-app. |

## Revoke / rotate

The App Password can be deleted anytime at
<https://myaccount.google.com/apppasswords> — then create a new one and
update `SMTP_PASSWORD` on Render. No code changes are ever needed; all
credentials live in environment variables.
