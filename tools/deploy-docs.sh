#!/usr/bin/env bash
# tools/deploy-docs.sh — manage the docs WebDAV deployment
#
# Configuration is read from .env at the repo root (gitignored).
# Copy .env.example to .env and fill in your credentials before running.
#
# Subcommands:
#   deploy          Upload docs/ to the WebDAV server via curl (default)
#   mount           Mount the WebDAV share as a local volume
#   unmount         Unmount the WebDAV share
#   --dry-run       Print what 'deploy' would upload without uploading

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
DOCS_DIR="$REPO_ROOT/docs"

SUBCOMMAND="${1:-deploy}"
DRY_RUN=false
[[ "$SUBCOMMAND" == "--dry-run" ]] && { SUBCOMMAND="deploy"; DRY_RUN=true; }

# ── Load .env ──────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found." >&2
  echo "       Copy .env.example to .env and fill in your credentials." >&2
  exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
  export "$line"
done < "$ENV_FILE"

# ── Validate required variables ────────────────────────────────────────────
for var in WEBDAV_URL WEBDAV_REMOTE_PATH WEBDAV_USER WEBDAV_PASS; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: $var is not set in $ENV_FILE" >&2
    exit 1
  fi
done

REMOTE_BASE="${WEBDAV_URL%/}/${WEBDAV_REMOTE_PATH#/}"  # server root + remote subfolder

# ── Subcommands ────────────────────────────────────────────────────────────

cmd_deploy() {
  echo "Deploying: $DOCS_DIR → $REMOTE_BASE"
  $DRY_RUN && echo "(dry run — no files will be uploaded)"
  echo ""

  find "$DOCS_DIR" -type f | sort | while IFS= read -r file; do
    relative="${file#"$DOCS_DIR"/}"
    remote="$REMOTE_BASE/$relative"

    if $DRY_RUN; then
      echo "  would upload: $relative"
    else
      echo "  ↑ $relative"
      if ! curl --silent --fail --show-error \
        --user "$WEBDAV_USER:$WEBDAV_PASS" \
        --upload-file "$file" \
        "$remote"; then
        echo "  warning: failed to upload $relative"
      fi
    fi
  done

  echo ""
  echo "Done."
}

cmd_mount() {
  local volume_name="${WEBDAV_VOLUME_NAME:-}"
  local mount_path="/Volumes/$volume_name"

  if [[ -n "$volume_name" ]] && mount | grep -q "$mount_path"; then
    echo "Already mounted at $mount_path"
    return 0
  fi

  echo "Mounting $REMOTE_BASE …"
  osascript -e "mount volume \"$REMOTE_BASE\" as user name \"$WEBDAV_USER\" with password \"$WEBDAV_PASS\""

  if [[ -n "$volume_name" ]]; then
    echo "Mounted at /Volumes/$volume_name"
  else
    echo "Mounted. Set WEBDAV_VOLUME_NAME in .env to the name that appeared under /Volumes/."
    echo "Currently mounted WebDAV volumes:"
    mount | grep "webdavfs" | awk '{print "  " $3}' || true
  fi
}

cmd_unmount() {
  local volume_name="${WEBDAV_VOLUME_NAME:-}"

  if [[ -z "$volume_name" ]]; then
    echo "error: WEBDAV_VOLUME_NAME is not set in $ENV_FILE" >&2
    echo "       Set it to the volume name that appears under /Volumes/ after mounting." >&2
    exit 1
  fi

  local mount_path="/Volumes/$volume_name"

  if ! mount | grep -q "$mount_path"; then
    echo "Not mounted: $mount_path"
    exit 0
  fi

  echo "Unmounting $mount_path …"
  diskutil unmount "$mount_path"
  echo "Done."
}

# ── Dispatch ───────────────────────────────────────────────────────────────
case "$SUBCOMMAND" in
  deploy)   cmd_deploy ;;
  mount)    cmd_mount ;;
  unmount)  cmd_unmount ;;
  *)
    echo "usage: deploy-docs.sh [deploy|mount|unmount|--dry-run]" >&2
    exit 1
    ;;
esac
