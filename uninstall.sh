set -e

SCRIPT_NAME=psnat3resolver

log "Removing a command shortcut (symlink)..."
rm -f /usr/local/bin/$SCRIPT_NAME
