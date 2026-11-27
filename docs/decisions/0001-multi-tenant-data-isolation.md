# 0001: Multi-tenant data isolation

Status: accepted, Nov 26, 2026; updated Nov 27.

## Context

- Each company's tickets, customers and agents must never be visible to another company. A leak between tenants is the worst failure this product can have, and it can't be undone.
- Design target: 500 companies, 10 agents each, about 100k messages a day and 110M over 3 years, on one Postgres 18 server.

## Options considered

| Option | Verdict | Why |
|---|---|---|
| company_id column with app scoping only | Rejected | Simplest, but isolation rests entirely on app code: one missed scope leaks data |
| Schema per tenant | Rejected | Strong isolation and clean per-tenant deletion, but 500 migration runs per deploy, partly migrated states, UNIONs for cross-tenant queries, catalog bloat |
| Database per tenant | Rejected | Strongest isolation, but multiplies connections, backups and migrations by 500 |
| company_id column, app scoping and Postgres row-level security | Chosen | Keeps the column approach's simplicity and adds a database-enforced backstop |

## Decision

- Every tenant table has company_id, with indexes that start with it.
- App scoping (acts_as_tenant) scopes queries and fills in company_id on new records, so mistakes fail loudly in the app.
- Postgres RLS policies enforce isolation in the database, so a missed scope returns nothing instead of another company's rows.
- Built in week one, because retrofitting roles and tenant context later is costly.
- Foreign key checks skip RLS, so an insert could point a company A ticket at a company B customer. Foreign keys are composite, (company_id, customer_id) referencing customers(company_id, id), with a matching unique index on the parent table, so a cross-tenant reference can't exist. Rails supports this without a gem: add_foreign_key with column arrays, and foreign_key: [:company_id, :customer_id] on belongs_to (with primary_key: [:company_id, :id] where the parent's primary key is just id; confirm the exact options when implementing).
- The schema format is SQL (config.active_record.schema_format = :sql, committing structure.sql). RLS settings, policies, the SECURITY DEFINER functions and grants can't be represented in schema.rb, and the test database is built from the schema file, so without this the tests would run with no policies at all. Rails then runs pg_dump and psql, and pg_dump refuses a newer server, so CI installs postgresql-client-18 from the PGDG apt repository and local development uses Homebrew's postgresql@18 (production doesn't dump the schema). Rails dumps the schema with --no-privileges, so structure.sql carries no grants.

## How the tenant reaches the database

- The connection checkout callback sets app.company_id from Current.company_id with set_config(…, false); no tenant means a reset. Checkin resets it.
- Rails 7.2+ may lease connections per query rather than per request, so the tenant is set on every checkout, not once per request. A test confirms this holds in Rails 8.1 (see Tests). The cost is one small SET per checkout.
- One helper is the only way the tenant is ever set. It sets app.company_id on the connection first, then loads the Company (which is under RLS, so it would return nothing in the other order), and sets Current.company_id and ActsAsTenant.current_tenant together (acts_as_tenant keeps its own setting, so nothing else links the two layers). Its main caller is the auth concern on every request: the session read happens before any tenant exists, on a connection the checkout callback has already passed. The other callers are sign-up after creating the company, the inbound-mail job after its lookup, and admin "switch to company."
- Rejected alternative: SET LOCAL inside a transaction around each request and job. It can't leak and survives PgBouncer, but every request becomes one transaction: all-or-nothing writes, longer locks and moved commit timing. Normal Rails transaction behavior won.

## Policies and roles

- Policies read company_id = NULLIF(current_setting('app.company_id', true), '')::bigint. After a RESET the setting is an empty string, not NULL, and a direct cast would throw.
- Owner role runs migrations.
- App role is not a superuser and is subject to RLS.
- Admin role has BYPASSRLS (or a dedicated policy) for the admin console's cross-company reads; every such read goes to the audit log. It gets its own connection pool and credentials, selected with connected_to, so ordinary app queries can never run on the connection that bypasses RLS.
- The roles are chaosdesk_owner, chaosdesk_app and chaosdesk_admin. db/roles.sql creates them, once per Postgres server; db/grants.sql sets ownership and default privileges, once per database. bin/db-bootstrap runs both and is safe to rerun. The servers use all of it; CI uses it only to create the roles, since Rails builds the test database itself.
- Inbound mail finds the company from the address through a SECURITY DEFINER lookup function, before any tenant is set. The function has a fixed search path (SET search_path = pg_catalog, public), returns only the company ID, and has EXECUTE revoked from PUBLIC and granted only to the app role.
- ALTER DEFAULT PRIVILEGES FOR ROLE (the owner) grants the app role new tables and new sequences automatically: sequences need USAGE because every Rails insert calls nextval() for its ID, and a table grant doesn't cover that. The admin role gets SELECT on new tables too, since BYPASSRLS skips policies but not privileges; write access only if the console turns out to need it. EXECUTE on new functions is revoked from PUBLIC globally, without IN SCHEMA: Postgres grants it to everyone as a global default, and a per-schema setting can only add to the global defaults, never remove from them. Each lookup function also gets an explicit REVOKE. FOR ROLE matters: default privileges apply only to objects that role creates.
- Sign-in finds users through a second SECURITY DEFINER lookup function, by email or by a user ID read from a token's signature (the full token check runs after the tenant is set), returning only the user and company IDs, with the same hardening as the inbound-mail one. The sessions table is off RLS. Details in 0005.
- App scoping has matching exceptions. Session is not an acts_as_tenant model, since it's read before any tenant exists. With require_tenant on (mistakes fail loudly), the sign-in lookup, the session read and the inbound-mail lookup run inside ActsAsTenant.without_tenant, or they raise NoTenantSet before RLS is reached. Sign-up runs without a tenant too: the companies table has an RLS policy on id = NULLIF(current_setting('app.company_id', true), '')::bigint, so sign-up creates the company through a narrow SECURITY DEFINER function, then sets the tenant through the helper. The five exceptions, across both layers: inbound mail, sign-in, sessions, sign-up and the admin role.

## Consequences

- Better: for most bugs, a leak needs two separate failures at once, a missed scope and a stale tenant on the connection. One schema and one migration run per deploy. Cross-tenant reads for admin and metrics go through one audited role.
- Worse: RLS depends on the checkout and checkin callbacks always running. A missing tenant returns empty results, which makes bugs quiet. Three database roles to manage. Every new entry point (jobs, Action Cable, the console) must set the tenant. Deleting or exporting one tenant means finding its rows across every table. The sessions table has zero layers of isolation, not one, so outside the current session it's reached only through a tenant-scoped user (Current.company.users.find(id).sessions). The two layers aren't fully independent: app scoping and RLS both get the tenant from the one helper, so a bug that sets Current wrong (in the auth concern or the switch helper) leaks with one failure. The admin role bypasses RLS, so a bug there is a leak on its own. Its password sits in the app containers, since the admin pool runs inside the app: the separate pool prevents accidental bypass, not a compromised container. That limit is accepted. The code that sets Current stays small and heavily tested.

## Tests

- A query with no tenant set returns no rows.
- A freshly checked-out connection has no tenant.
- A request after an error path doesn't inherit the previous tenant.
- With app scoping bypassed, RLS still blocks another company's rows.
- An insert referencing another company's row fails on the composite foreign key.
- A schema scan finds every table with a company_id column and checks that RLS is enabled and a policy exists. Tables that have a company_id but aren't tenant-scoped are on an explicit allowlist: today just sessions (0005). Tables without the column, like Solid Queue's and Action Mailbox's, aren't flagged and don't need listing.
- Two queries in one request, with a forced connection checkout between them, both see the tenant.
- The suite runs as the app role, the way production connects. Specs connect as the database superuser so Rails can rebuild the test database (its purge drops and recreates it), then rails_helper grants chaosdesk_app access to all tables and sequences and reconnects as chaosdesk_app, so every spec runs under RLS. The grants run before the reconnect; after it, the app role can't grant anything. Specs that create company data set the tenant first, since an insert with no tenant is refused. RLS tests count only on that setup.
- Checked against a bootstrapped database, not in the spec suite, because the test database is rebuilt from structure.sql (which carries no grants or revokes) and the suite grants only the app role: in a database the owner has migrated, the app role can insert a row (default privileges and sequence grants work), the lookup functions can't be executed by the admin role or PUBLIC, and the admin role can read another company's rows.
- A company can't read another company's row in the companies table.

## Revisit when

- PgBouncer in transaction mode is added: per-connection settings break, so move to SET LOCAL.
- One tenant grows far larger than the rest, or the messages table passes a few hundred GB: consider partitioning or sharding by tenant.
