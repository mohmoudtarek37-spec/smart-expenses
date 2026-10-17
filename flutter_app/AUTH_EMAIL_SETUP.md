# Hesabaty 2.0: Direct signup without email activation (owner decision)

Project: `uusnulmlygtpgwecyuvc`

## Current rollout

The product owner has decided to **skip email activation** and **postpone
purchasing a domain**. Email/password signup should create a session
immediately without requiring a confirmation message.

**Owner action required** (this cannot be changed by client code or SQL):
1. Open https://supabase.com/dashboard/project/uusnulmlygtpgwecyuvc/auth/providers
2. Open the Email provider settings.
3. Keep Email sign-in **enabled** and new user signups **allowed**.
4. Turn **Confirm Email OFF** and save.
5. Install the latest Android preview and test signup with a new test address
   owned by you. New signup should return both a user and an active session.
6. Sign out/sign back in. Check that `auth.users` receives the test user
   and cloud finance records remain separate across accounts.

## Gmail / Resend

- Temporary support email: `matarekstudio@gmail.com`, already publicly
  listed in the app privacy policy. A Gmail address is NOT the same as a
  custom-domain sender for Resend.
- Resend can remain unused until a verified sending domain is purchased;
  it is NOT required for **instant signup** when Confirm Email is off.
- If email delivery is later needed without a purchased domain, use a
  properly configured SMTP provider. Google's SMTP can use app passwords
  with 2-step verification, subject to provider restrictions; a Gmail
  password must NEVER be sent in chat or committed to GitHub.
- Password reset, change-email security notifications and similar
  actions still need functional transactional email delivery.

## Security and product limitations

Disabling Confirm Email is convenient but carries an identity-proof risk:
anyone can reserve an email address they don't own. Supabase may mark the
account email as confirmed even though ownership was never proven.

*Never link/merge a Google OAuth identity to an existing password account
solely because the unverified signup email matches.* Add abuse controls,
and consider re-enabling verification when proper email delivery exists.
Preserve Row Level Security and user-isolated encrypted local stores.
Do not claim production auth is verified without real device tests.

References:
- https://supabase.com/docs/guides/auth/general-configuration
- https://supabase.com/docs/guides/auth/passwords
- https://supabase.com/docs/guides/auth/auth-smtp
- https://supabase.com/docs/guides/troubleshooting/using-google-smtp-with-supabase-custom-smtp-ZZzU4Y

## Future

Once a domain is purchased and verified, enable custom SMTP in Supabase
(Resend is a possible provider) and update the official support address.
No change to users' existing account emails is required just to change
the sender/support address.
