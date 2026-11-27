# 0002: Deploying the API

Status: accepted, Nov 26, 2026; updated Nov 27.

## Context

- The API runs on two Oracle Cloud Always Free ARM VMs, staging and production, 1 core and 6 GB each. Each VM also runs Postgres.
- Budget is free tiers only, so no paid platform.
- The project's main goal is learning what goes into running an app in production, so a deploy that hides its mechanics teaches less.
- CI builds one ARM image per change on GitHub's ARM runners. The same image goes to staging automatically, then to production on approval, never rebuilt.
- Two weeks of evenings for the foundation.

## Options considered

| Option | Verdict | Why |
|---|---|---|
| Docker Compose plus a hand-written deploy script | Chosen | Nothing hidden; light on a 6 GB VM; fits the time box |
| Kamal | Not now | Rails 8's default and light, with zero-downtime deploys, TLS and rollbacks built in. It would hide exactly the pieces this project is meant to teach |
| Kubernetes (k3s, one cluster per VM) | Later | The industry standard and a long-term goal, but its setup (manifests, ingress, certificates, secrets) would likely use up the time box alone |
| Self-hosted platform (Coolify, Dokku) | Rejected | Heroku-like and the most hidden of all |
| Free hosted platforms (Render's free tier) | Rejected | Free services spin down when idle, which breaks email processing, and free Postgres expires after 30 days |

## Decision

- Each VM runs the app, its job workers and Postgres with Docker Compose, behind Caddy, which handles HTTPS.
- A deploy script, run from CI, does the release: pull the image, migrate, start the new container, check health, switch traffic, stop the old one.
- Server setup is scripted too, so a reclaimed or lost VM is rebuilt from scratch with a redeploy.
- Postgres stays outside the deploy: its own Compose project (or deploys that touch only the app and workers, with --no-deps) and a named volume, so no app deploy can recreate or restart the database.
- Proxy: Caddy. It sits in front of the app, gets and renews HTTPS certificates automatically, and the deploy script switches traffic by rewriting the Caddyfile and running caddy reload, so the zero-downtime swap stays hand-built. The admin API listens only on localhost inside Caddy's own container, reached through docker compose exec, so a compromised app container can't reroute traffic. Traefik (label-based discovery) adds hidden behavior; kamal-proxy would do the swap itself.
- Registry: GitHub Container Registry. Where CI stores built images for the VMs to pull. Free for public images and uses the same authentication as Actions.
- Both are cheap to swap later: a registry change touches one CI step and one pull command; a proxy change touches its config and the switch step.
- Secrets: stored as GitHub environment secrets (staging and production separately). The deploy script writes them to two root-only env files on the VM; they're never baked into the image. .env.app holds DATABASE_URL (the app role's URL), ADMIN_DATABASE_URL (the admin role's URL), RAILS_MASTER_KEY, the Resend key and the Action Mailbox relay password, and is read by the web and worker containers. .env.migrate holds only DATABASE_URL, set to the owner role's URL, and is read only by the one-off migrate container, which is how "only the migrate step uses the owner URL" is enforced. Simple, and every step can be explained.
- Database layout: one Postgres database per environment, with Solid Cache, Solid Queue and Solid Cable in their own tables, instead of Rails 8's default of four production databases. Lighter on a 6 GB VM and one set of grants and default privileges. Solid Queue, Cache and Cable ship their tables as `db/*_schema.rb` files that db:migrate never loads, so they become regular migrations, and the libraries' connects_to settings are removed.

## How a deploy runs

Proposed mechanics, to confirm while building:

The web app runs in two slots, two Compose services named web_blue and web_green, because one Compose service can't run two images at once. Each deploy goes to the idle slot.

1. CI tags the image with the git commit and pushes it to the registry. One deploy per environment at a time: a GitHub Actions concurrency group per environment, plus a lock on the VM taken with flock, so two deploys can't race on migrations or the proxy switch, and a crashed deploy can't leave a stale lock behind.
2. CI connects over SSH as a deploy-only user with a dedicated key, kept in GitHub's environment secrets; production's key is available only after approval. The script pulls the new tag.
3. Migrations run in a one-off container of the new image, using the owner role's database URL (record 0001). The app and workers use the app role's URL, so each environment has two database URLs, and only this step uses the owner one. Each release only expands, so migrations work with both old and new code; contraction ships in a later release, after the old code is gone. The migrate container boots with only .env.migrate: SECRET_KEY_BASE_DUMMY=1 keeps the master key out, the admin database URL may be absent, and a CI check proves the migrate command boots with just that file. The admin pool's database.yml entry has database_tasks: false, so migrations never run as the admin role. strong_migrations enforces the safe patterns.
4. The new web container starts in the idle slot and must pass a readiness check before getting traffic: an endpoint that runs a trivial query against Postgres. Rails' /up only confirms the app booted.
5. The script writes the active slot into the Caddyfile, then runs caddy reload through docker compose exec (reload goes through the admin API inside Caddy's own container). The Caddyfile's directory is bind-mounted from the VM, not the single file: a single-file mount pins the inode, so the usual write-a-temp-file-and-mv would leave the container reading the old file while reload reports success. Recreating the container keeps the active slot. After reload, the script asks Caddy's admin API for the live upstream and checks it matches the intended slot. One source of truth: the file always shows what's live. The old slot is stopped after its requests finish, not removed, so it stays available for rollback; it's replaced only when the next deploy uses it.
6. The job workers are replaced: old workers get SIGTERM and finish within Solid Queue's shutdown timeout, then new ones start. Old and new code overlap briefly, so job arguments must work across one version, like migrations: a job enqueued by new code can reach an old worker.
7. A smoke test runs against the environment's URL.
8. Rollback starts the old slot, waits for its readiness check, and switches Caddy back; if the slot is gone, it redeploys the previous commit's image. The workers are rolled back too, replaced with the previous image the same way as step 6, so a rollback caused by a broken job doesn't leave that job running. That's safe only because migrations only add; a migration is never rolled back as part of a deploy rollback.

Script details: image cleanup always keeps the previous tag, or the old slot can't restart and rollback quietly falls back to a fresh pull. The web slots use restart: unless-stopped; with always, a stopped old slot would start again after a VM or Docker restart and sit in memory running old code.

## Consequences

- Better: every step of a deploy is code you wrote and can explain. Low memory overhead on small VMs. The k3s migration later becomes a before-and-after story.
- Worse: zero-downtime swaps, health checks and rollbacks are hand-built, with room for subtle bugs, and the script is code that needs testing. One VM per environment means no redundancy: a VM restart is downtime. Compose shows up in fewer job postings than Kamal or Kubernetes. The deploy user is in the docker group, which is effectively root on the VM: "deploy-only" describes what CI is meant to do, not what its key could do.

## Revisit when

- The help desk's later versions start: the planned k3s migration, with its own record.
- The deploy script starts reimplementing what Kamal or Kubernetes already provide.
