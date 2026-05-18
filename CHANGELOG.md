# Changelog

All notable changes to `SacredVote-Email-Config` are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This is a CONFIGURATION repo (postfix / dovecot / opendkim overlays
+ deployment helpers), not a Rust crate — there is no semantic-
versioning contract on the file layout, but version-like milestones
are still useful for operators tracking what's in production.

## [Unreleased]

(No unreleased changes.)

## 2026-05-04 — `bdb30ce` — press@ + security@ aliases

### Added
- `postfix/aliases` entries for `press@sacredvote.org` and
  `security@sacredvote.org`, both forwarding to `alerts@sacred.vote`.
  Round-trip tested via the `mail` CLI in both directions
  (incoming to press@/security@ landing in alerts@'s inbox; replies
  from alerts@ resolving correctly).

## 2026-05-03 — `17b0853` — license relicense (MIT → FSL-1.1-MIT)

### Changed
- `LICENSE` switched to FSL-1.1-MIT (Functional Source License). Source-
  available now; auto-converts to MIT in two years. Same pattern as the
  rest of the PlausiDen ecosystem repos that flipped to FSL-1.1-MIT
  around the same time. The license change is forward-looking: anyone
  cloning today gets FSL terms; the MIT auto-conversion clause means
  anyone cloning two years from now (or pulling the future-MIT-marked
  commits) gets MIT.

## 2026-05-03 — `c9d2f71` + `29ae139` — README warning banner

### Added
- `README.md` opens with a prominent **DO NOT USE — UNVERIFIED**
  banner referencing the AVP-2 doctrine. The initial wording (#29ae139)
  was tightened to "In Development — Unverified" (#c9d2f71) to soften
  the client-facing tone while still publishing the "every commit is
  guilty until proven innocent" stance.

## 2026-05-02 — `41ae219` — `deploy.sh` v0.1 (issue #344)

### Added
- `deploy.sh` — idempotent overlay deployer. Defaults to **dry-run**
  so a fresh clone never accidentally writes to live `/etc/postfix/`,
  `/etc/dovecot/`, `/etc/opendkim/`. Set `APPLY=1` to commit changes;
  the script diffs every overlay file against the live target and
  prints what would change before any write. Re-runnable safely
  after `git pull` — only touches files whose content differs from
  the repo.

## 2026-05-01 — `e0de891` — initial bootstrap

### Added
- Initial repo layout following the Mailroom adoption playbook:
  - `postfix/` — `main.cf`, `master.cf`, `aliases`, virtual-mailbox
    + alias maps
  - `dovecot/` — `dovecot.conf` + auth, mail, ssl partials
  - `opendkim/` — `opendkim.conf` + `KeyTable` + `SigningTable` +
    `TrustedHosts` (DKIM signing across all 3 tenant domains)
  - `nginx/` — Roundcube webmail vhost snippet for `mail.sacred.vote`
  - `systemd/` — service drop-ins for postfix + dovecot + opendkim
  - `env/` — operator env-var template (paths, passwords, domains)
  - `docs/` — `ADOPTING.md`, `DNS-RECORDS.md`, threat model

## Pulling Mailroom updates

Per `docs/ADOPTING.md`, you don't pull Mailroom into this repo —
you pull Mailroom into `~/Mailroom-build` on the VPS and rebuild the
overlay by re-running this repo's `deploy.sh APPLY=1`. The
sacred.vote / sacredvote.org tenant config is intentionally NOT
upstreamed into Mailroom (Mailroom is generic; this repo is the
tenant-specific layer).
