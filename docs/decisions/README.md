# Decision records

This repo also holds the records that span both repos; the Vue repo's README links to them.

## Records

- [0001: Multi-tenant data isolation](0001-multi-tenant-data-isolation.md)
- [0002: Deploying the API](0002-deploying-the-api.md)
- [0003: Where the API runs](0003-where-the-api-runs.md)
- [0004: Domains and origins](0004-domains-and-origins.md)
- [0005: Authentication, and deferring tokens](0005-authentication-and-deferring-tokens.md)

## Still to draft

Backend and database, two repos, the compatibility rule, budget and cloud, metrics.

1. Domains (done: 0004).
2. Auth and deferred tokens (done: 0005).
3. The compatibility rule. It constrains every deploy from the start: the API stays compatible with the previous frontend release for at least one release. Expand-only migrations and job arguments that work across one version are the same rule at other layers, and 0002 already relies on it. Say how you check it: Playwright running the previous frontend build against the new API, or the OpenAPI diff if you adopt rswag.
4. Two repos. It explains why there are two, how they stay in step (the published image, the API contract, Playwright running from the Vue repo), and the cost: changes that span both repos need two PRs in order.
5. Backend and database. These are mostly the stack choices you already know. The interesting parts are Postgres 18 and waiting on 19, and the Ruby 4 and Rails 8.1 version reasoning (generated on 8.1.4.1). It's short.
6. Budget and cloud. Free tiers plus one domain, and how the setup maps onto AWS (EC2, RDS, S3, IAM). This record can link to the planned "How this would run on AWS" write-up rather than repeat it.
7. Metrics. Grafana Cloud over self-hosting, what gets measured (request latency, error rate, queue depth, time since last inbound email), and the free tier's limits on retention and series.
