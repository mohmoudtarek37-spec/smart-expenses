# Hesabaty 2.0 — Email signup and Resend SMTP setup

Status: NOT configured automatically.
Supabase project reference: uusnulmlygtpgwecyuvc.
Do not put SMTP API keys/passwords, Supabase secret/service-role keys or user
account credentials in the public GitHub repo.

## Why email signup fails
Supabase's default SMTP is intended for development. Without custom SMTP it
only sends confirmation emails to pre-authorized members of your organization.
Other addresses will get "Email address not authorized". Other possible
problems: email signups disabled, internet connectivity, bad credentials or
email confirmation not completed. On the latest server check there were
0 users. Flutter CI alone cannot confirm signup.

## Owner-only email setup
1. At https://resend.com create a Resend account and add a sending domain
   you own. Verify the DNS records (DKIM/SPF) until domain status Verified.
   A shared gmail.com or github.io address is not an owned sending domain.
2. Recommended: open https://supabase.com/partners/resend while signed into
   Supabase, click Add integration, choose the Hesabaty project, and approve
   the connection in the browser. The integration can provision credentials
   and configure SMTP without handling API keys manually.
3. Manual alternative: go to
   https://supabase.com/dashboard/project/uusnulmlygtpgwecyuvc/auth/smtp
   and enable Custom SMTP. Sender name Hesabaty. Sender address must be
   no-reply@YOUR_VERIFIED_DOMAIN. Host smtp.resend.com, port 465,
   user resend, password PRIVATE_RESEND_API_KEY.
   Enter the password privately in Supabase settings only, never in chat
   or GitHub.
4. In Supabase Authentication > Providers > Email, enable email/password
   signups, keep Confirm Email enabled, and verify valid URL configuration.
   Do not disable confirmation to conceal missing SMTP configuration.
5. Test a brand-new email on latest Android debug APK: Create account,
   receive confirmation email, confirm it and sign in. Test the resend
   confirmation link and then test a second account. Check Auth logs when
   errors occur. Never use real financial data until cloud sync is verified.
6. Security: confirm user_snapshots RLS isolates data per authenticated
   account. Automatic safe sync and Google sign-in are separate open tasks.

Resend free plan at review: 3000 emails/month, 100/day, 3 verified domains.
Supabase custom SMTP initially has a separate limit of 30 emails/hour.

References:
https://supabase.com/docs/guides/auth/auth-smtp
https://resend.com/docs/send-with-supabase-smtp
https://resend.com/docs/dashboard/domains/introduction
https://supabase.com/partners/resend

STATUS: signup must still be tested end-to-end with a real Android device
and an actual email; a successful APK does not prove it is fixed.
