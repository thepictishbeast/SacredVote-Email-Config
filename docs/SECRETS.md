# Secrets — regeneration recipes

Every secret in this repo is a placeholder. The real values live at
`/etc/...` on the VPS, mode 600. Use these recipes to mint fresh values
when you need to rotate.

> **HARD rule** — `feedback_no_mail_password_rotation`: never rotate
> dovecot mailbox hashes without explicit permission from the user. The
> live `/etc/dovecot/users` file is authoritative; this repo's
> `dovecot/users.example` is redacted-only.

## Mailbox passwords (dovecot)

Each row in `dovecot/users.example` has a redacted hash. Regenerate one:

```sh
PW=$(openssl rand -base64 36 | tr -d '/+=' | head -c 32)
HASH=$(sudo doveadm pw -s SHA512-CRYPT -p "$PW")
# Example: add a fresh mailbox (DON'T overwrite an existing line — see HARD rule above)
echo "newbox@sacred.vote:${HASH}::5000:8::/var/mail/vhosts/sacred.vote/newbox::" \
  | sudo tee -a /etc/dovecot/users >/dev/null
sudo systemctl reload dovecot
echo "Password for newbox@sacred.vote: $PW"
unset PW HASH
```

Save `$PW` somewhere out-of-band (1Password, sealed env file, paper)
**before** you `unset` it. The hash is one-way; lose the plaintext and
you must rotate.

## DKIM private keys

Never committed to this repo (`.gitignore` blocks `*.private`). Each
domain has its own key. To rotate `sacred.vote`:

```sh
DOMAIN=sacred.vote
SELECTOR=$(date -u +sv%Y%m)   # e.g., sv202605 — must be a NEW selector
sudo install -d -o opendkim -g opendkim -m 0750 /etc/opendkim/keys/$DOMAIN
cd /etc/opendkim/keys/$DOMAIN
sudo opendkim-genkey -b 2048 -d $DOMAIN -s $SELECTOR
sudo chown opendkim:opendkim $SELECTOR.private $SELECTOR.txt
sudo chmod 600 $SELECTOR.private
sudo chmod 644 $SELECTOR.txt

# 1. Add new entry to /etc/opendkim/key.table:
#    $SELECTOR._domainkey.$DOMAIN $DOMAIN:$SELECTOR:/etc/opendkim/keys/$DOMAIN/$SELECTOR.private
# 2. Update /etc/opendkim/signing.table to point *@$DOMAIN to the new selector.
# 3. sudo systemctl restart opendkim
# 4. Publish $SELECTOR.txt as a TXT record at $SELECTOR._domainkey.$DOMAIN at Cloudflare.
# 5. Wait 24-48h, verify with:
#      dig +short TXT $SELECTOR._domainkey.$DOMAIN
#      swaks --to check-auth@verifier.port25.com --from alerts@$DOMAIN \
#        --server mail.sacred.vote --port 587 --auth LOGIN \
#        --auth-user alerts@$DOMAIN
# 6. Once aggregate DMARC reports show new selector signing cleanly,
#    remove the old `default` entries from key.table + signing.table and
#    delete the old TXT record.
```

For `sacredvote.org`, repeat with `DOMAIN=sacredvote.org` and a different
selector (e.g., `svorg202605`) — the keys MUST be distinct (see
`docs/DNS-RECORDS.md`).

## Watchtower SMTP password

Used by `plausiden-watchtower` to relay Page-severity alerts via
`alerts@sacredvote.org`. Lives at `/etc/sacred-vote/alerts-smtp.env`.

```sh
PW=$(openssl rand -base64 36 | tr -d '/+=' | head -c 32)
HASH=$(sudo doveadm pw -s SHA512-CRYPT -p "$PW")
# Replace the existing line (HARD rule still applies — confirm with operator first)
sudo sed -i "s|^alerts@sacredvote.org:.*|alerts@sacredvote.org:${HASH}::5000:8::/var/mail/vhosts/sacredvote.org/alerts::|" /etc/dovecot/users
sudo systemctl reload dovecot
sudo sed -i "s|^SMTP_PASS=.*|SMTP_PASS=\"$PW\"|" /etc/sacred-vote/alerts-smtp.env
sudo chmod 600 /etc/sacred-vote/alerts-smtp.env
sudo systemctl restart plausiden-watchtower  # or whatever consumes the env file
unset PW HASH
```

> **HARD rule** — `feedback_no_tim_email_sender`: never use
> `tim@sacred.vote` as an automated sender. `alerts@sacredvote.org` is
> the canonical outbound mailbox for tooling.

## ntfy token

Lives at `/etc/sacred-vote/ntfy.env` (mode 600). To rotate:

```sh
NEW_TOKEN=$(openssl rand -hex 32)
# 1. Add the new token to the local ntfy server's user/token store.
# 2. Replace the value in /etc/sacred-vote/ntfy.env:
sudo sed -i "s|^NTFY_TOKEN=.*|NTFY_TOKEN=\"$NEW_TOKEN\"|" /etc/sacred-vote/ntfy.env
sudo chmod 600 /etc/sacred-vote/ntfy.env
# 3. Reload anything sourcing the env (systemd units, Watchtower, alert scripts).
# 4. Revoke the old token in the ntfy server's auth store.
unset NEW_TOKEN
```

## Cloudflare DNS-Edit token

Used by Caddy for ACME DNS-01 challenges. Lives at
`/etc/caddy/cloudflare.env` (mode 600). Token scope MUST be: **DNS:Edit
on `sacred.vote` and `sacredvote.org` zones only** — never account-wide.

To rotate:

1. Generate a fresh token at `dash.cloudflare.com → My Profile → API
   Tokens → Create Token → Edit zone DNS`.
2. Restrict zone resources to exactly `sacred.vote` + `sacredvote.org`.
3. Replace the value in `/etc/caddy/cloudflare.env`:
   ```sh
   sudo sed -i 's|^CF_API_TOKEN=.*|CF_API_TOKEN="<paste-new-token>"|' /etc/caddy/cloudflare.env
   sudo chmod 600 /etc/caddy/cloudflare.env
   sudo systemctl restart caddy
   ```
4. Revoke the old token in the Cloudflare dashboard.

## SacredVote app session signing keys

Live in `/etc/sacred-vote/<service>.env` per service. To rotate any:

```sh
openssl rand -hex 32   # 64-char hex; mode 600 in the target env file
```

Restart the consuming service after rotation.

## GitHub PAT

Used by the VPS for `git pull/push` against the private SacredVote repos.
Stored at `/home/admin/.git-credentials` and `/home/admin/.secure/github-pat.env`
(both mode 600). To rotate:

```sh
# 1. Generate a new PAT at github.com/settings/tokens (classic, scope: repo).
# 2. Replace the file:
echo "https://thepictishbeast:<new-pat>@github.com" > /home/admin/.git-credentials
chmod 600 /home/admin/.git-credentials
# 3. Update /home/admin/.secure/github-pat.env identically.
# 4. Revoke the old PAT at github.com/settings/tokens.
```

## SSH host key (sacred-vote VPS)

If the VPS host key is compromised, regenerate ALL of `/etc/ssh/ssh_host_*`,
`systemctl restart ssh`, then update `~/.ssh/known_hosts` on every operator
laptop and the Termux phone (`reference_phone_ssh_alias`).

## Emergency rotation drill — "what if a private key leaked"

1. Detect: alert from Watchtower, GitHub secret-scanning, or operator
   noticing `*.private` in a diff.
2. **STOP THE LEAK FIRST** — `git filter-repo` or `git filter-branch`
   purge from history, force-push, then rotate the credential.
3. Mint new key per the recipe above.
4. Publish new DKIM TXT (if DKIM key) or update consumer config (if env
   token).
5. Revoke old key/token.
6. Diff `git log --all --full-history -- '*.private' '*.env' '*.pem'` to
   prove the leak is gone.
7. File a postmortem at `~/.claude/notes/` with the timeline.
