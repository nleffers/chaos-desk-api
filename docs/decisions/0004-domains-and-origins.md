# 0004: Domains and origins

Status: accepted, Nov 26, 2026; updated Nov 27.

## Context

- The frontend and API are separate apps, hosted separately: the Vue app on Cloudflare, the API on Oracle VMs (records 0002 and 0003).
- Auth is cookie sessions, so the browser has to treat the frontend and API as the same site.
- Inbound email needs mail records (MX) on a domain you control.
- HTTPS needs a real hostname, not a bare IP address.

## Options considered

| Option | Verdict | Why |
|---|---|---|
| One owned domain, separate app. and api. subdomains | Chosen | Same site, so cookie sessions work; each subdomain points at its own host; matches the separate deploys |
| One owned domain, with /api proxied to Rails | Rejected | Avoids CORS, but the frontend host would have to proxy every API call to Oracle, adding a hop and coupling the two deploys |
| The hosts' default URLs (*.workers.dev, the VM's IP) | Rejected | Different registrable domains are cross-site, so cookies don't flow; no mail records to control; no certificate for a bare IP |

## Decision

- The domain is nleffers.dev (about $12 a year, the project's only cost): a personal domain rather than a product one, so ChaosDesk, every later project and a portfolio home page all live on its subdomains, and a resume carries one address. The .dev ending requires HTTPS in every browser, which costs nothing here.
- Names are flat, one level, with a chaosdesk- prefix: chaosdesk-app., chaosdesk-api., chaosdesk-in., chaosdesk-mail. and later chaosdesk-portal.; staging adds staging- in front (staging-chaosdesk-app. and so on). Elsewhere in these records and the plan, app., api., in., mail., portal. and their staging- forms are shorthand for these names.
- app. serves the Vue app, api. serves Rails; the React customer portal later adds portal..
- Never serve the app from a host's default URL. On Cloudflare that means workers_dev = false, at least for the production Worker.
- CORS on the API allows exact origins per environment, with credentials: the staging frontend can call only the staging API.
- SameSite=Lax doesn't stop requests from sibling subdomains, so the API checks the Origin header (or a token header) for CSRF protection.
- The CSRF check applies only to cookie-authenticated routes. Server-to-server routes (the Email Worker posting to Action Mailbox, provider webhooks) send no Origin and no session, so they use their own authentication: the relay password or a signature check.
- The session cookie is named `__Host-session`. Browsers then require Secure, Path=/ and no Domain, so no sibling subdomain can set or override it (cookie tossing, which enables session fixation). The plan puts future projects on this domain, which makes this matter. One line in the auth generator's code.
- api. is DNS-only in Cloudflare, not proxied: traffic goes straight to the VM, Caddy sees real visitor IPs, and Rails' rate_limit works as written. Proxying later (hiding the VM's IP, DDoS protection) is a deliberate change: Caddy and Rails would then trust Cloudflare's IP ranges and read CF-Connecting-IP, or every user shares one rate limit.
- Staging uses flat names, staging-app. and staging-api., each allowed only by the staging API. Nested names like app.staging. fall outside Cloudflare's free one-level certificate and complicate the CAA record; flat names avoid both.
- Registrar and DNS: Cloudflare Registrar, bought Nov 27, with DNS in the same account as Email Routing and the frontend's Workers.

## Proposed details

To confirm while building:

- Inbound mail: its own subdomain for the MX record, per environment (staging: staging-in.). Companies forward their support address to one on it (for example acme@in.), and replies come back to generated addresses (`reply+<token>@in.`), so Email Routing uses a catch-all rule that sends everything to the Worker. Check that Email Routing supports subdomains in its current form.
- Outbound mail: sent from your domain (staging: staging-mail.), never as the company's own address: for example `"Acme Support" <acme@mail.>`, with Reply-To set to the reply address. SPF and DKIM on the sending subdomain, DMARC on the root domain. DMARC starts at p=none (added Nov 27, with no reporting address yet; Cloudflare's DMARC Management can supply one), then moves to quarantine and reject once reports show mail passing SPF and DKIM; going straight to reject can silently drop your own mail during setup.
- Staging never emails real customers: an Action Mailer interceptor in staging drops or redirects any recipient not on an allowlist. The protection lives in code you control and tests cover it, rather than in a provider feature; Resend's test addresses serve automated checks.
- HSTS on app. and api.. The .dev ending is already preloaded for HTTPS at the browser level, so there's no root-domain preload decision to make.
- A CAA record covering both certificate sources. Caddy issues the API's certificates (api. is DNS-only): Let's Encrypt by default, with ZeroSSL as its fallback, whose CAA name is sectigo.com, so list both. Cloudflare issues the Worker domains' certificates as Advanced Certificates, and its automatic CAA records cover only Universal SSL, so its authorities are listed by hand. The full set: letsencrypt.org, sectigo.com, pki.goog; cansignhttpexchanges=yes, and ssl.com. A missing entry fails slowly: the current certificate works until renewal, then breaks about 60 days later. Inbound mail names need no certificate, since they carry only MX records.

## Consequences

- Better: cookie sessions work across the two apps; each app keeps its own host and deploy; one domain covers every future project.
- Worse: CORS and CSRF protection are configuration to get exactly right in every environment, and each new origin (the portal, a new environment) has to be added to both. Pull request previews on *.workers.dev are cross-site, so they're visual-only.

## Revisit when

- A frontend needs to live on a different registrable domain (for example, customers bringing their own domain for the portal).
