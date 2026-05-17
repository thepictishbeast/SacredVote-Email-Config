> ## In Development — Unverified
>
> This is an active engineering tree, not a release. APIs, file
> layouts, and behavior may change between commits. Tests pass
> locally; CI may or may not be green at any given moment.
>
> Source is published publicly for transparency and audit.

# SacredVote-Email-Config

**Private repo** — SacredVote's tenant-specific mail-stack deployment overlay
for the VPS hosting `sacred.vote` and `sacredvote.org`. The `/etc/...` files
actually running in production today, captured here so a fresh VPS can be
brought back up by `git clone + ./deploy.sh` instead of an ops-tribal-knowledge
restore.

Bootstrapped from `PlausiDen-Email-Config` template per
`Mailroom/docs/ADOPTING.md`.

## Where this fits

```
[ Mailroom ]                 ← generic implementation
  (public-shaped)              typed Sieve schema, mail-cli,
   thepictishbeast/Mailroom    Postfix/dovecot/opendkim templates
        │
        │ adopted by ↓
        │
        ├─ [ PlausiDen-Email-Config ]   ← upstream sibling (private)
        │     plausiden.com production overlay (web-01 VPS)
        │
        └─ [ SacredVote-Email-Config ]   ← THIS REPO (private)
              sacred.vote + sacredvote.org production overlay
              (sacred-vote VPS — separate host from web-01)
```

- **Mailroom** owns the *generic* code: typed `CategoryRule` schema, Sieve emitter, Postfix/dovecot/opendkim templates. Open-source-shaped.
- **This repo** is the SacredVote-tenant overlay: which mailboxes exist, which DKIM keys are published, which env-file values are live, which DNS records have been set at the registrar.

## Domains in this overlay

- `sacred.vote` — primary platform domain (mailboxes: `tim`, `admin`, `noreply`, `alerts`, `support`, `contact`, `info`, `router`, `vault`).
- `sacredvote.org` — separate live product per `project_sacredvote_org_separate`. Hosts organizational/legal mailboxes (`legal`, `privacy`, `security`) and acts as a forwarding alias for the `sacred.vote` platform mailboxes during the .vote → .org transition window.

## Layout

```
postfix/
  main.cf, master.cf       Postfix runtime captured from /etc/postfix/
  vmailbox                 site mailbox map (real values — no secrets)
  virtual                  alias map (sacredvote.org → sacred.vote during transition)

opendkim/
  opendkim.conf            relaxed/relaxed canonicalization, milter port
  key.table, signing.table per-domain DKIM signing wiring
  trusted.hosts            internal IPs that bypass signing checks
  keys/                    PUBLIC keys only — `default.txt` (the DNS-publish form).
                           Private keys (.private) are NEVER in this repo
                           and are blocked by .gitignore.

dovecot/
  conf.d/*.conf            relevant subset of /etc/dovecot/conf.d/
  dovecot.conf             top-level dovecot config
  users.example            virtual mailbox roster — hashes REDACTED to
                           {SSHA512}<REDACTED-DOVECOT-HASH>::...
                           Regenerate with: sudo doveadm pw -s SHA512-CRYPT

nginx/
  sacred.vote              voter-facing app vhost
  sacredvote.org           org-domain vhost
  mail.sacred.vote         IMAPS/SMTPS frontend (autodiscover, MTA-STS)
  files.sacred.vote        static-asset vhost

env/
  ntfy.env.example         /etc/sacred-vote/ntfy.env (alerting endpoint)
  alerts-smtp.env.example  /etc/sacred-vote/alerts-smtp.env (watchtower email)
  cloudflare.env.example   /etc/caddy/cloudflare.env (DNS-01 ACME)
                           — secrets REPLACED with <REDACTED-N+chars>.

systemd/
  caddy.service.d/         drop-ins: cloudflare.conf (sources cloudflare.env),
                           hardening.conf, onfailure.conf, oom-score.conf
  dovecot.service.d/       oom-score.conf
  postfix.service.d/       oom-score.conf

docs/
  DNS-RECORDS.md           complete DNS record set for sacred.vote +
                           sacredvote.org (MX, SPF, DKIM, DMARC, MTA-STS, etc.)
  SECRETS.md               regen recipes — one-liner per secret type.
  REPOS-INDEX.md           the SacredVote repo set this overlay supports.
```

## Known issues / open cleanup

- **`opendkim/opendkim.conf` line 8** still lists `plausiden.com` in the
  comma-separated `Domain` value. This is harmless (no `plausiden.com`
  entry exists in `key.table` or `signing.table`, so opendkim never tries
  to sign for it) but should be cleaned to `sacred.vote,sacredvote.org`
  on the next intentional opendkim restart. Captured as-is to faithfully
  mirror live `/etc/opendkim/opendkim.conf` until the operator schedules
  a service touch.

## Restoring the mail VPS from cold

```sh
git clone git@github.com:thepictishbeast/SacredVote-Email-Config.git
cd SacredVote-Email-Config

# 1. Dry-run: prints unified diffs for every /etc file the overlay
#    would change, exits 1 if any differ. Safe to run as non-root.
./deploy.sh

# 2. Apply (writes /etc — needs root). Confirms before each overwrite;
#    use --yes to skip the per-file confirm.
sudo ./deploy.sh --apply

# 3. Mint secrets per docs/SECRETS.md (dovecot user hashes, DKIM
#    private keys, env tokens). deploy.sh NEVER writes these.

# 4. Validate end-to-end: mail-admin validate
```

`deploy.sh` is conservative by design: dry-run by default, idempotent,
diff-before-write, and *never* touches `/etc/dovecot/users`,
`opendkim/keys/*.private`, or `env/*.env` (those follow `SECRETS.md`).
HARD rules from `feedback_no_mail_password_rotation` and
`feedback_no_tim_email_sender` are enforced in the script.

## Secret regeneration

See [docs/SECRETS.md](docs/SECRETS.md). One-line per secret on how to mint a fresh value (env tokens, mailbox passwords, DKIM private keys).

## DNS

See [docs/DNS-RECORDS.md](docs/DNS-RECORDS.md). The full set of records live at Cloudflare for `sacred.vote` and `sacredvote.org` — what's published, what's pending, and what each one is for.

## Pulling Mailroom updates

Per `Mailroom/docs/ADOPTING.md`, you don't pull Mailroom into this repo —
you pull Mailroom into `~/Mailroom-build` on the VPS and rebuild the
`mail-admin` CLI from there. Generic improvements should be PR'd back to
Mailroom; tenant-specific deltas stay here.

## What this repo is NOT

- **Not the runtime mail data.** Mail itself lives at `/var/mail/vhosts/.../{cur,new,...}` on the VPS and is backed up separately.
- **Not the Sieve rule source.** Those are in `Mailroom/mail-config/src/categories.rs` and emit into the deployed `categories.sieve` via `mail-admin emit-categories`.
- **Not the secrets themselves.** Every secret in this repo is a placeholder. Real values live in `/etc/...` on the VPS (mode 600) and are minted via the regen instructions in `docs/SECRETS.md`.
- **Not Tim's mailbox.** `tim@sacred.vote` is off-limits for automated mail per `feedback_no_tim_email_sender` (HARD). Use `alerts@sacredvote.org` for outbound.
