# 0003: Where the API runs

Status: accepted, Nov 26, 2026; updated Nov 27.

## Context

- Budget is free tiers only; nothing that expires or needs paying later.
- One server per environment has to fit Rails, the job workers, Postgres and Caddy.
- Staging should match production's infrastructure.
- AWS is the most common cloud in job postings, so the setup should map onto it (record on budget and cloud, still to draft).

## Options considered

| Option | Verdict | Why |
|---|---|---|
| Oracle Cloud Always Free ARM | Chosen | Up to 2 cores and 12 GB in total: room for the full stack, split into a matching staging and production. A real cloud VM with a public IP, firewall rules and SSH, close to EC2 |
| Google Cloud e2-micro | Rejected | Stable and always free, but about 1 GB of memory, too tight for Rails, Postgres and workers on one box |
| A machine at home with Cloudflare Tunnel | Rejected | Free and as powerful as the hardware, but uptime depends on home power and internet; least like production |
| AWS free plan | Rejected | Credits, not an always-free server; the account closes after 6 months or when credits run out. Planned later as a separate trial |
| Oracle Pay As You Go, staying inside free limits | Rejected | Reportedly keeps the larger 4-core allowance and avoids idle reclamation and capacity errors, but a card on file can be charged if usage ever goes over the free limits |

## Decision

- Two Always Free ARM VMs, 1 core and 6 GB each: staging and production.
- Plan for losing a VM. Oracle halved these limits in 2026 with no public announcement ([InfoQ](https://infoq.com/news/2026/07/oracle-cloud-free-tier-limits/)), and some existing instances were disabled after the August 18 change ([Oracle community forums](https://community.oracle.com/customerconnect/discussions/tagged/arm-compute/p1)). On top of that, Oracle may reclaim idle free VMs, and popular regions often run out of ARM capacity. So:
  - A setup script builds a new VM from scratch. Secrets are automatic: the deploy script writes them from GitHub environment secrets (0002). Both VMs hold reserved public IPs (the free tier allowed two, despite forum reports of one), so a rebuilt VM reattaches its old address with no DNS change. Caddy still requests new certificates on a fresh VM. Two steps stay manual for now: creating the VM and attaching its reserved IP in the Oracle console (scriptable later with Oracle's CLI or Terraform). Rebuild drills point Caddy at Let's Encrypt's staging endpoint, so repeated rebuilds don't hit certificate rate limits.
  - Backups go off the VM and outside the Oracle account, with a different provider, so an account problem can't take the backups with it. Cloudflare R2's free tier is the likely pick: Cloudflare is already in the plan, and R2 speaks the S3 protocol, so the AWS mapping holds.
  - All config lives in the repos.
  - Moving hosts, Oracle or otherwise, is a redeploy, not a rescue.
- The images are ARM, built on GitHub's free ARM runners (public repos only). CI jobs that run the API image, like Playwright, run on ARM too.

## Proposed server setup

To confirm while building: SSH by key only, with a deploy-only user for CI; only ports 80, 443 and SSH open, in both Oracle's network rules and the VM's own firewall; Docker installed by the setup script; automatic security updates. Only Caddy publishes ports (80 and 443); Postgres and the app are reachable only on the Docker network. Docker writes its own iptables rules, so a published port skips the VM's firewall: a published 5432 would expose Postgres with only Oracle's network rules in the way.

## Consequences

- Better: room for the whole stack on free hardware, a staging environment that truly matches production, and a provider-independent setup that makes the later AWS trial a redeploy.
- Worse: provider risk is real: Oracle can change terms or reclaim the idle staging VM, so the rebuild script will likely get used, not just exist. No redundancy: a VM restart is downtime. Both environments live in one Oracle account, so an account-level problem takes down staging and production together; backups survive it, since they live with another provider. ARM adds a build step.

## Checks

- A rebuild drill: the first one is building production from nothing in week one, using only the setup script and a deploy, timed. Later drills rebuild staging.
- A restore drill from the off-VM backups (shared with the backups checklist item).

## Revisit when

- Oracle changes its Always Free terms again, or reclaims a VM more than once.
- The AWS trial starts.
- There's budget for a paid VPS, for example after landing a job.
