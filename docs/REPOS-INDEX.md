# Repos index — what this overlay supports

This config repo deploys the mail stack for the **SacredVote** brand on the
VPS that hosts `sacred.vote` and `sacredvote.org`. Below is the wider repo
constellation the mail stack interacts with: who sends mail, who receives
notifications, who emits the alerts.

## Mail stack

| Repo | Visibility | What | Lineage |
|---|---|---|---|
| [`Mailroom`](https://github.com/thepictishbeast/Mailroom) | private (public-shaped) | Generic mail-stack toolkit. Typed `CategoryRule` schema, sieve emitter, `mail-cli` (`mail-admin`), Postfix/dovecot/opendkim templates. | **upstream of all email work** |
| [`PlausiDen-Email-Config`](https://github.com/thepictishbeast/PlausiDen-Email-Config) | private | PlausiDen-tenant overlay. Sibling of this repo. Used as the bootstrap template for new tenant overlays. | downstream of Mailroom |
| **`SacredVote-Email-Config`** | private | **THIS REPO.** SacredVote-tenant overlay (`sacred.vote` + `sacredvote.org`). | downstream of Mailroom |

## SacredVote application stack

These repos send/receive mail through this overlay.

| Repo | Visibility | What | Mail role |
|---|---|---|---|
| [`Sacred.Vote`](https://github.com/thepictishbeast/Sacred.Vote) | private | Voter-facing app: registration, voting, identity verification. | sends transactional mail via `noreply@sacred.vote`; receives support replies via `support@`/`contact@` |
| [`sacredvote.org`](https://github.com/thepictishbeast/sacredvote.org) | private | Separate live product (NOT a redirect of `.vote`) per `project_sacredvote_org_separate`. Org/legal/marketing surface. | sends from `info@sacredvote.org`; receives `legal@`, `privacy@`, `security@` |
| [`plausiden-watchtower`](https://github.com/thepictishbeast/plausiden-watchtower) | private | Per-chain log watcher + auto-Claude fix loop (project_plausiden_watchtower). | sends Page-severity alerts via `alerts@sacredvote.org` SASL→`mail.sacred.vote:587` |
| [`sacredvote-crypto`](https://github.com/thepictishbeast/sacredvote-crypto) | private | Voter-side crypto primitives (Belenios glue, ZK identity wires). | no direct mail role; failures surface via Watchtower → alerts@ |
| [`sacredvote-zktls`](https://github.com/thepictishbeast/sacredvote-zktls) | private | zkTLS verifier — Utah DLD / mDL flow. | no direct mail; verification-failure alerts surface via Watchtower |
| [`sacredvote-webauthn`](https://github.com/thepictishbeast/sacredvote-webauthn) | private | Passkey ceremony codepath (admin/Tim/voters share one impl). | no direct mail role |
| [`sacredvote-gatekeeper`](https://github.com/thepictishbeast/sacredvote-gatekeeper) | private | Gatekeeper service (rate-limit, fraud detection). | abuse-style alerts route to `security@sacredvote.org` via Watchtower |
| [`sacredvote-analytics`](https://github.com/thepictishbeast/sacredvote-analytics) | private | Two-tier analytics + ZKP per `project_data_privacy_architecture`. | no direct mail role |
| [`SacredVote-Tests`](https://github.com/thepictishbeast/SacredVote-Tests) | private | Cross-repo integration tests (Tier 0 of the testing trio). | optional CI alert email to `alerts@sacredvote.org` |

## Standards / methodology repos (read-only consumers of this stack)

| Repo | Visibility | What |
|---|---|---|
| [`PlausiDen-Loom`](https://github.com/thepictishbeast/PlausiDen-Loom) | private | Typed UI doctrine — design tokens, typed components, lint CLI. **Single source of truth for UI** in PlausiDen + SacredVote repos. |
| [`PlausiDen-Audits`](https://github.com/thepictishbeast/PlausiDen-Audits) | private | Vendored audit scripts (e.g., `audit-raw-elements.mjs`). Used by every PlausiDen + SacredVote repo's CI / `npm prebuild`. |
| [`PlausiDen-AVP-Doctrine`](https://github.com/thepictishbeast/PlausiDen-AVP-Doctrine) | private | Operational standing orders for AI agents touching this code (AVP-2). |
| [`plausiden-standards`](https://github.com/thepictishbeast/plausiden-standards) | private | Cross-repo standards source-of-truth (CSS gates, raw-element gates, etc.). |

## Other plausiden ecosystem repos (sibling, not downstream of this overlay)

| Repo | What |
|---|---|
| [`Thundercrab`](https://github.com/thepictishbeast/Thundercrab) | Privacy-first mail client. Iced GUI, federated rule learning, schema-compatible with `Mailroom`'s `CategoryRule`. |
| [`PlausiDen-CMS`](https://github.com/thepictishbeast/PlausiDen-CMS) | Generic CMS (Axum + Maud). Multi-tenant. |
| [`Patina`](https://github.com/thepictishbeast/Patina) | Rust learning environment. |

## Naming convention

| Pattern | Meaning |
|---|---|
| `SacredVote-X` (CamelCase prefix + hyphen + CamelCase) | SacredVote-internal infrastructure / tooling, generally private. |
| `sacredvote-x` (lowercase) | SacredVote application sub-services (analytics, crypto, gatekeeper, …). |
| `<Brand>-Email-Config` | Per-tenant email overlay carrying `/etc/...` deployment templates + DNS state + secret-regen recipes. |
| `<Generic>` (no prefix) | Either community-shaped (`Mailroom`, `Patina`, `Thundercrab`) or pre-rename. |
