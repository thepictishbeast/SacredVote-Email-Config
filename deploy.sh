#!/usr/bin/env bash
#
# deploy.sh — SacredVote-Email-Config v0.1 deploy automation (#344)
#
# Lays this overlay down on top of /etc/{postfix,opendkim,dovecot,nginx,
# caddy,systemd}/ on a Debian VPS. Default mode is dry-run: every
# planned action is printed but nothing is written. Pass --apply to
# actually mutate /etc.
#
# Design constraints (these are intentional — do not "fix" without
# reading the comments first):
#
#   - Idempotent. Re-running with --apply on a synced host is a no-op.
#   - Dry-run by default. `git clone + ./deploy.sh` prints the diff
#     against live /etc/ without touching anything, so the operator
#     can review before authorizing changes.
#   - Diffs are unified. Every file the script would change is
#     diff'd against the live copy before write.
#   - Secrets are NEVER managed here. dovecot/users (real password
#     hashes), opendkim/keys/*.private (real DKIM private keys),
#     env/*.env (real Cloudflare/SMTP/ntfy secrets) are not in this
#     repo and not in this script. They follow docs/SECRETS.md regen
#     recipes — separate, deliberate workflows. See HARD rules below.
#   - HARD rules honored:
#       * feedback_no_mail_password_rotation — script never rewrites
#         /etc/dovecot/users. Even with --apply it skips that file.
#       * feedback_no_tim_email_sender — tim@sacred.vote sender config
#         is not touched by this script.
#       * feedback_never_modify_authorized_keys — script never goes
#         near ~/.ssh.
#
# Exits 0 on dry-run-clean / apply-success; 1 on diff (dry-run) /
# error; 2 on missing pre-flight requirement (not root, wrong distro,
# package missing).
#
# Usage:
#   ./deploy.sh                # dry-run, exits 1 if any file differs
#   ./deploy.sh --apply        # actually write changes; needs root
#   ./deploy.sh --apply --yes  # same but skip the per-section confirm

set -euo pipefail

# --- arg parsing ------------------------------------------------------

APPLY=0
ASSUME_YES=0
VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    --help|-h)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      echo "see ./deploy.sh --help" >&2
      exit 2
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Track whether any file differed; non-zero exit on dry-run if so.
DIFFS_FOUND=0
FILES_PLANNED=0
FILES_WRITTEN=0

# Track which services need a touch after writes succeed.
declare -A TOUCH

# --- helpers ----------------------------------------------------------

log()  { printf '\033[36m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[deploy:warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[31m[deploy:err]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[32m[deploy:ok]\033[0m %s\n' "$*"; }

# Confirm before a section runs in --apply mode. Skipped under --yes.
confirm() {
  if [[ $APPLY -eq 0 ]]; then return 0; fi
  if [[ $ASSUME_YES -eq 1 ]]; then return 0; fi
  printf '\033[35m[deploy:confirm]\033[0m %s [y/N] ' "$*"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# plan_file <repo-relative-source> <absolute-target> [touch-service]
#
# Diffs the repo file against the live target. In dry-run, prints the
# diff and accumulates DIFFS_FOUND. In --apply, copies the file
# preserving mode/owner if the target dir requires (defaults to root).
plan_file() {
  local src="$1"
  local target="$2"
  local touch_service="${3:-}"
  local src_abs="$REPO_ROOT/$src"

  if [[ ! -f "$src_abs" ]]; then
    err "source missing: $src (skipping)"
    return 1
  fi
  FILES_PLANNED=$((FILES_PLANNED + 1))

  if [[ ! -e "$target" ]]; then
    log "NEW  $target  (would be created from $src)"
    DIFFS_FOUND=$((DIFFS_FOUND + 1))
    if [[ $APPLY -eq 1 ]]; then
      install -D -m 0644 "$src_abs" "$target"
      FILES_WRITTEN=$((FILES_WRITTEN + 1))
      [[ -n "$touch_service" ]] && TOUCH[$touch_service]=1
      ok "wrote $target"
    fi
    return 0
  fi

  # File exists — diff it. If we can't read the live file (root-owned
  # config and we're running as a non-root user during dry-run), treat
  # it as "unknown — review under sudo" rather than failing the run.
  if [[ ! -r "$target" ]]; then
    log "UNKNOWN $target  (not readable by $(id -un); re-run with sudo for content diff)"
    DIFFS_FOUND=$((DIFFS_FOUND + 1))
    return 0
  fi
  if diff -u "$target" "$src_abs" >/tmp/.deploy-diff.$$ 2>&1; then
    [[ $VERBOSE -eq 1 ]] && log "SAME $target"
    rm -f /tmp/.deploy-diff.$$
    return 0
  fi

  log "DIFF $target  (overlay $src vs live)"
  cat /tmp/.deploy-diff.$$
  rm -f /tmp/.deploy-diff.$$
  DIFFS_FOUND=$((DIFFS_FOUND + 1))

  if [[ $APPLY -eq 1 ]]; then
    if confirm "overwrite $target with overlay version?"; then
      install -m 0644 "$src_abs" "$target"
      FILES_WRITTEN=$((FILES_WRITTEN + 1))
      [[ -n "$touch_service" ]] && TOUCH[$touch_service]=1
      ok "wrote $target"
    else
      warn "skipped $target (operator declined)"
    fi
  fi
}

# plan_tree <repo-rel-dir> <target-dir> [touch-service]
plan_tree() {
  local src_dir="$1"
  local target_dir="$2"
  local touch_service="${3:-}"
  local src_abs="$REPO_ROOT/$src_dir"

  if [[ ! -d "$src_abs" ]]; then
    err "source dir missing: $src_dir"
    return 1
  fi

  while IFS= read -r -d '' f; do
    local rel="${f#"$src_abs"/}"
    plan_file "$src_dir/$rel" "$target_dir/$rel" "$touch_service"
  done < <(find "$src_abs" -type f -print0)
}

# --- pre-flight -------------------------------------------------------

log "SacredVote-Email-Config deploy v0.1 — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "mode: $([[ $APPLY -eq 1 ]] && echo APPLY || echo DRY-RUN)"
log "repo: $REPO_ROOT"
echo

if [[ $APPLY -eq 1 && $EUID -ne 0 ]]; then
  err "--apply requires root (writing to /etc/...)"
  exit 2
fi

if ! command -v lsb_release >/dev/null 2>&1 || \
   ! lsb_release -d 2>/dev/null | grep -qi debian; then
  warn "host is not Debian — paths may differ; proceeding anyway"
fi

for pkg in postfix dovecot-core opendkim; do
  if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    warn "package not installed: $pkg  (deploy will plan files but services will fail until installed)"
  fi
done

echo

# --- postfix ----------------------------------------------------------

log "=== postfix ==="
plan_file postfix/main.cf      /etc/postfix/main.cf      postfix
plan_file postfix/master.cf    /etc/postfix/master.cf    postfix
plan_file postfix/vmailbox     /etc/postfix/vmailbox     postfix
plan_file postfix/virtual      /etc/postfix/virtual      postfix
echo

# --- opendkim ---------------------------------------------------------
#
# We deploy the lowercase Debian path names since this overlay's host is
# Debian. The Mailroom resolver (post-#343) accepts either convention.
# We never deploy the .private keys — those follow SECRETS.md regen.

log "=== opendkim ==="
plan_file opendkim/opendkim.conf  /etc/opendkim.conf      opendkim
plan_file opendkim/key.table      /etc/opendkim/key.table opendkim
plan_file opendkim/signing.table  /etc/opendkim/signing.table opendkim
plan_file opendkim/trusted.hosts  /etc/opendkim/trusted.hosts opendkim
# Public DNS-publish forms — useful for "does this match what's published?".
plan_tree opendkim/keys           /etc/opendkim/keys      opendkim
echo

# --- dovecot ----------------------------------------------------------
#
# Skipping /etc/dovecot/users (the real password hashes file). That
# file is managed via SECRETS.md per feedback_no_mail_password_rotation
# and must NEVER be overwritten by a script.

log "=== dovecot ==="
plan_file dovecot/dovecot.conf  /etc/dovecot/dovecot.conf  dovecot
plan_tree dovecot/conf.d        /etc/dovecot/conf.d        dovecot
warn "skipping /etc/dovecot/users — managed by SECRETS.md per feedback_no_mail_password_rotation"
echo

# --- nginx ------------------------------------------------------------

log "=== nginx ==="
plan_file nginx/sacred.vote        /etc/nginx/sites-available/sacred.vote        nginx
plan_file nginx/sacredvote.org     /etc/nginx/sites-available/sacredvote.org     nginx
plan_file nginx/mail.sacred.vote   /etc/nginx/sites-available/mail.sacred.vote   nginx
plan_file nginx/files.sacred.vote  /etc/nginx/sites-available/files.sacred.vote  nginx
echo

# --- systemd drop-ins -------------------------------------------------

log "=== systemd drop-ins ==="
plan_tree systemd/caddy.service.d   /etc/systemd/system/caddy.service.d   caddy
plan_tree systemd/dovecot.service.d /etc/systemd/system/dovecot.service.d dovecot
plan_tree systemd/postfix.service.d /etc/systemd/system/postfix.service.d postfix
if [[ $FILES_WRITTEN -gt 0 ]]; then
  TOUCH[systemd-daemon-reload]=1
fi
echo

# --- env files (NEVER deployed; only enumerated) ----------------------

log "=== env (placeholders only — real values per SECRETS.md) ==="
for f in env/*.example; do
  [[ -f "$f" ]] || continue
  target="/etc/$(basename "${f%.example}")"
  case "$(basename "$f")" in
    cloudflare.env.example) target="/etc/caddy/cloudflare.env" ;;
    ntfy.env.example|alerts-smtp.env.example) target="/etc/sacred-vote/$(basename "${f%.example}")" ;;
  esac
  if [[ -e "$target" ]]; then
    ok "$target exists (real secrets present)"
  else
    warn "$target MISSING — mint per docs/SECRETS.md before starting services"
  fi
done
echo

# --- summary ----------------------------------------------------------

log "=== summary ==="
echo "  files planned: $FILES_PLANNED"
echo "  files differing: $DIFFS_FOUND"
if [[ $APPLY -eq 1 ]]; then
  echo "  files written:  $FILES_WRITTEN"
fi

# Bash 4.x quirk: ${assoc[@]} on an empty associative array trips
# `set -u`; the +x form is the standard workaround.
if [[ -n "${TOUCH[*]+set}" ]]; then
  echo
  log "post-deploy actions (run as root):"
  for svc in "${!TOUCH[@]}"; do
    case "$svc" in
      systemd-daemon-reload) echo "  systemctl daemon-reload" ;;
      postfix)               echo "  postmap /etc/postfix/vmailbox /etc/postfix/virtual && systemctl reload postfix" ;;
      opendkim)              echo "  systemctl restart opendkim" ;;
      dovecot)               echo "  systemctl restart dovecot" ;;
      nginx)                 echo "  nginx -t && systemctl reload nginx" ;;
      caddy)                 echo "  systemctl reload caddy" ;;
      *)                     echo "  systemctl reload $svc" ;;
    esac
  done
fi

echo
if [[ $APPLY -eq 0 ]]; then
  if [[ $DIFFS_FOUND -gt 0 ]]; then
    log "dry-run found $DIFFS_FOUND difference(s). Re-run with --apply to write."
    exit 1
  else
    ok "live /etc state matches overlay. Nothing to do."
    exit 0
  fi
else
  if [[ $FILES_WRITTEN -gt 0 ]]; then
    ok "applied $FILES_WRITTEN change(s). Run the post-deploy actions above, then: mail-admin validate"
  else
    ok "no changes needed."
  fi
  exit 0
fi
