# 0005: Authentication, and deferring tokens

Status: accepted, Nov 26, 2026; updated Nov 27.

## Context

- Version 1's only clients are browsers: agents using the Vue app. Customers come later, through the React portal, with their own sign-in decision.
- The Vue app and the API sit on sibling subdomains of one domain (0004), so cookies work between them.
- The API runs in Rails API mode, which drops cookies, sessions and CSRF protection by default.
- The tenant comes from the signed-in user (0001), so auth is where Current.company_id starts.

## Options considered

| Option | Verdict | Why |
|---|---|---|
| Rails 8 authentication generator, cookie sessions | Chosen | Generated code you own and can explain line by line; sessions live in the database |
| Devise | Rejected | Mature, with invitations and lockout nearly free, but built around HTML flows and Warden; in API mode you work around its defaults, and much happens out of sight |
| Token auth now (JWT or bearer tokens) | Deferred | Serves non-browser clients, which don't exist yet; brings token storage in the browser, refresh and revocation for no current user |
| A separate auth service shared by future projects | Rejected | Built for clients that may never come. At work, a shared auth app meant for every app still serves one app a decade later |

## Decision

- The Rails 8 generator provides User, a database-backed Session model and an Authentication concern. Controllers are reworked to return JSON.
- The cookies middleware is added back in API mode. A signed cookie holds only the session's ID; the session itself lives in the database.
- The cookie is `__Host-session`: Secure, HttpOnly, SameSite=Lax (0004).
- CSRF protection: an Origin check on every cookie-authenticated route (0004). CORS allows exact origins with credentials; the frontend sends credentials: 'include'.
- One seam. The Authentication concern sets Current.user, and from it Current.company_id for 0001. Nothing else in the app knows how a user signed in.
- Sign-in is rate limited twice, by IP and by the email submitted (rate_limit's by: option), so slow guessing against one account from many addresses is stopped too. Company sign-up gets the same IP rate limit, since it's unauthenticated and creates rows through a SECURITY DEFINER function. All use Rails' built-in rate_limit.
- Built by hand: company sign-up, agent invitations, and two roles (admin and agent).
- Sessions can be revoked: "log out everywhere," and the admin console can see and end a user's sessions. Outside the current session, sessions are reached only through a tenant-scoped user (Current.company.users.find(id).sessions), since the sessions table has no isolation of its own.
- Outbound email in week one: Resend's free tier (3,000 a month, 100 a day). Password reset and invitations need real email from the foundation on, earlier than the inbound-email slice, and SPF and DKIM get set up in week one. Both sending subdomains, chaosdesk-mail. and staging-chaosdesk-mail., were accepted on the free plan and verified (US region, open and click tracking off). Cloudflare's own sending needs a paid Workers plan.
- One company per agent in version 1, so Current.company_id follows directly from the user, with no company picker. An agent's email address is unique across the app: sign-in goes email, user, company. Agents in several companies would be an additive change later: a memberships table plus the switch helper from 0001.
- Sessions expire, enforced on the server from timestamps on the session row: an inactivity timeout and an absolute maximum lifetime (proposed: two weeks idle, 30 days total). The generator's permanent cookie and never-expiring sessions are changed. last_seen_at is written at most once a minute, not on every request.
- Resetting a password ends every existing session for that user, since a reset often follows a compromised account. The reset email goes through deliver_later, so a known email returns as fast as an unknown one.
- Sign-in and password reset return the same response whether or not the email exists. Timing matches too: on an unknown email, the flow still compares against a dummy password hash, so a miss takes as long as a real bcrypt check (what Rails' authenticate_by does, done by hand here since the flow is custom). Sign-up still reveals that an email is taken, because emails are unique across the app; that trade-off is accepted.
- Sign-in happens before a tenant is set, so it gets a narrow way past RLS (0001). The sessions table is off RLS: it holds only user and company IDs and metadata, and the cookie's ID is the secret. It's on 0001's allowlist by name, since its company_id column would otherwise trip the schema scan. Users are found through a SECURITY DEFINER lookup function that takes an email, or a user ID read from a token's signature (password reset, invitations), and returns only the user ID and company ID. The concern then sets the tenant through 0001's helper and loads the full user under RLS, so the table holding password hashes stays protected. Only then does the full token check (find_by_token_for) run, since it compares the token's embedded data against the loaded user. The function gets the same hardening as the inbound-mail lookup.
- Role checks (admin, agent) live in one small hand-written authorization concern, not spread across controllers, consistent with owning the auth code. Pundit is the natural step if permissions grow past two roles.
- The session row stores company_id beside user_id. A session never changes company in version 1, so an ordinary request reads the tenant straight from the session, sets it, and loads the user under RLS, with no lookup call per request.
- Inviting an agent creates a pending user right away. Accepting the invitation goes through the same token lookup as password reset, so no separate invitations table needs another way past RLS.
- Email uniqueness is enforced by a global unique index. Under RLS and app scoping, a uniqueness validation only sees one company, so sign-up and invitations rescue RecordNotUnique into an "email taken" error instead of returning a 500. The rescue is the guard; a check through the sign-in lookup could give a friendlier early error, but check-then-insert races, so it never replaces the rescue.
- Company sign-up runs before any tenant exists: it creates the company through a narrow SECURITY DEFINER function (companies is under RLS, 0001), then sets the tenant through 0001's helper and creates the admin user.

## Tokens, deferred

- Trigger: the first non-browser client, which is Public API v1.
- Tokens are added beside sessions, not instead of them, as another branch in the same concern. Browsers keep using cookie sessions.
- The OAuth provider comes later still, on top of the same seam.

## Consequences

- Better: every line of auth is code you can explain. Database sessions give revocation and an audit trail. The seam makes tokens an addition, not a migration.
- Worse: invitations, sign-up and JSON responses are yours to build and test. There is no lockout or email confirmation out of the box. Cookie auth across subdomains needs CORS, CSRF and cookie settings exactly right in every environment.

## Tests

- Requests without a valid session are rejected.
- A cookie-authenticated request with a foreign Origin is rejected.
- Revoking a session signs that browser out on its next request.
- Sign-in attempts past the rate limit are refused.
- The session cookie is set as `__Host-session`, Secure and HttpOnly.
- A session past its idle timeout or maximum lifetime is rejected.
- Resetting a password ends every existing session for that user.
- Sign-in and password reset responses are identical for known and unknown emails in body, and on an unknown email the dummy hash comparison runs (checked by spying on the bcrypt call, not by measuring response times, which is flaky on shared CI runners).
- Repeated sign-ins against one email from different IPs hit the per-email limit. Rate-limit tests use a memory cache store, since the test environment's default cache is a null store.
- The sign-in lookup function returns only the user ID and company ID, and no other columns are reachable through it.
- An agent request to an admin-only action is refused by the authorization concern.
- A request with only a session cookie sets the tenant from the session row and loads the user under RLS.
- A pending user can't sign in until the invitation is accepted.
- Signing up with an email already used at another company returns "email taken," not a 500.
- A tampered token fails at the full check after the tenant is set.
- Session endpoints refuse another company's user ID.
- request.remote_ip is the client's address, not Caddy's. RSpec can't prove this, since the request has to pass through Caddy, so it's part of the staging smoke test.

## Revisit when

- Public API v1 starts: add tokens.
- The React customer portal starts: customer sign-in is its own decision.
- The OAuth provider starts.
