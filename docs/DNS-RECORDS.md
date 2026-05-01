# DNS records — `sacred.vote` + `sacredvote.org` at Cloudflare

Both zones live at Cloudflare. Apex names are CF-proxied (orange-cloud);
mail-related hostnames (`mail.sacred.vote`, future `mta-sts.*`) MUST be
DNS-only (grey-cloud) so SMTP/STARTTLS isn't intercepted.

VPS public IPv4: **`45.32.65.175`** (no IPv6 mail at present).

## sacred.vote — live (verified resolving 2026-05-01)

| Host | Type | Value | Purpose | Proxy |
|---|---|---|---|---|
| `@` | A | `45.32.65.175` (origin) | apex — site | CF-proxied |
| `@` | AAAA | (none — IPv4-only origin) | — | — |
| `www` | A | (same as apex) | site | CF-proxied |
| `mail` | A | `45.32.65.175` | MX target — Postfix/dovecot frontend | **DNS-only** |
| `files` | A | (CF-proxied) | static-asset vhost | CF-proxied |
| `@` | MX 10 | `mail.sacred.vote.` | inbound mail | — |
| `@` | TXT | `v=spf1 ip4:45.32.65.175 -all` | SPF (hard-fail; only the VPS sends) | — |
| `default._domainkey` | TXT | `v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkq...` (full key in `opendkim/keys/sacred.vote/default.txt`) | DKIM (selector `default`) | — |
| `_dmarc` | TXT | `v=DMARC1; p=none; rua=mailto:admin@sacred.vote;` | DMARC (still in observation; will tighten to `quarantine` once DKIM/SPF aggregate reports look clean) | — |

## sacredvote.org — live (verified resolving 2026-05-01)

| Host | Type | Value | Purpose | Proxy |
|---|---|---|---|---|
| `@` | A | `45.32.65.175` (origin) | apex — site | CF-proxied |
| `@` | MX 10 | `mail.sacred.vote.` | inbound mail (delegated to the `.vote` mail host) | — |
| `@` | TXT | `v=spf1 ip4:45.32.65.175 -all` | SPF (hard-fail) | — |
| `default._domainkey` | TXT | `v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkq...` (full key in `opendkim/keys/sacredvote.org/default.txt`) | DKIM (selector `default`) — **distinct key from `sacred.vote`**, NOT a copy | — |
| `_dmarc` | TXT | `v=DMARC1; p=quarantine; rua=mailto:admin@sacred.vote; fo=1` | DMARC (already at quarantine — org-domain mail is lower-volume so we tightened earlier) | — |

## Pending publish (not yet live)

### MTA-STS — `sacred.vote`

| Host | Type | Value |
|---|---|---|
| `mta-sts` | A | `45.32.65.175` (DNS-only) |
| `_mta-sts` | TXT | `v=STSv1; id=<YYYYMMDDHHMMSSZ>` (refresh on policy change) |

After A propagates: `sudo certbot --expand --nginx -d mta-sts.sacred.vote`
(or via Caddy/Cloudflare DNS-01 — see `env/cloudflare.env.example`). Then
serve `mta-sts.txt` from `/.well-known/mta-sts.txt` per RFC 8461.

### MTA-STS — `sacredvote.org`

| Host | Type | Value |
|---|---|---|
| `mta-sts` | A | `45.32.65.175` (DNS-only) |
| `_mta-sts` | TXT | `v=STSv1; id=<YYYYMMDDHHMMSSZ>` |

### TLS-RPT (both zones)

| Host | Type | Value |
|---|---|---|
| `_smtp._tls.sacred.vote` | TXT | `v=TLSRPTv1; rua=mailto:tlsrpt@sacred.vote` |
| `_smtp._tls.sacredvote.org` | TXT | `v=TLSRPTv1; rua=mailto:tlsrpt@sacred.vote` |

(Single inbox at `tlsrpt@sacred.vote` is fine for both; create the mailbox
in `postfix/vmailbox` + `dovecot/users` when you publish these records.)

### DNSSEC (both zones)

DS records pending — blocked on `project_tomorrow_reminders` (Tim has the
registrar account). Once published, MTA-STS becomes belt-and-suspenders
on top of DANE.

## Verification commands

```sh
# sacred.vote
dig +short MX  sacred.vote
dig +short TXT sacred.vote
dig +short TXT default._domainkey.sacred.vote
dig +short TXT _dmarc.sacred.vote
dig +short A   mail.sacred.vote
dig +short A   mta-sts.sacred.vote
dig +short TXT _mta-sts.sacred.vote
dig +short TXT _smtp._tls.sacred.vote

# sacredvote.org
dig +short MX  sacredvote.org
dig +short TXT sacredvote.org
dig +short TXT default._domainkey.sacredvote.org
dig +short TXT _dmarc.sacredvote.org
dig +short A   mta-sts.sacredvote.org
dig +short TXT _mta-sts.sacredvote.org
dig +short TXT _smtp._tls.sacredvote.org

# Live deliverability sanity check (against Google's DKIM/SPF/DMARC parser):
swaks --to check-auth@verifier.port25.com --from alerts@sacredvote.org \
  --server mail.sacred.vote --port 587 --auth LOGIN \
  --auth-user alerts@sacredvote.org --auth-password "$(sudo cat /etc/sacred-vote/alerts-smtp.env | grep ^SMTP_PASS | cut -d= -f2 | tr -d '"')"
```

## Why two distinct DKIM keys?

`sacred.vote` and `sacredvote.org` each have their own `default._domainkey`
TXT record with **independent** RSA-2048 public keys. This is intentional:

1. **Domain-scoped revocation.** If one private key leaks we rotate that
   selector without touching the other domain's deliverability.
2. **DMARC alignment.** With `aspf=relaxed; adkim=relaxed`, mail from
   `alerts@sacredvote.org` aligns on the `.org` DKIM key, not the `.vote`
   key, even though both are signed by the same opendkim instance.
3. **Cross-domain reuse anti-pattern.** Sharing one key would couple the
   two zones' reputations together. They're distinct products
   (`project_sacredvote_org_separate`) and need distinct reputations.

The keys are wired in `opendkim/signing.table` and `opendkim/key.table`.
