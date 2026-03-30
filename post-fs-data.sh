#!/system/bin/sh
# post-fs-data.sh
# Runs very early in boot (before APEX packages are mounted by the system).
#
# Two-stage protection:
#   Stage 1 — Normal mode: scan /data/apex/active and remove corrupted entries.
#   Stage 2 — Bootloop mode: if this script has run 3+ times without a
#             successful boot (service.sh never got to reset the counter),
#             wipe ALL of /data/apex/active to force a clean slate.
#             Other KSU/Magisk modules in /data/adb/modules/ are NEVER touched.
#
# Counter file : $MODDIR/bootcount   (inside this module's own directory)
# Log file     : /data/local/tmp/apex_cleaner.log

MODDIR=${0%/*}
LOG_FILE="/data/local/tmp/apex_cleaner.log"
APEX_ACTIVE_DIR="/data/apex/active"
BOOTCOUNT_FILE="$MODDIR/bootcount"

# How many consecutive failed boots before we wipe the whole folder
BOOTLOOP_THRESHOLD=3

###############################################################################
# Logging helpers
###############################################################################

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_separator() {
    echo "================================================================================" >> "$LOG_FILE"
}

###############################################################################
# Log rotation — keep last 200 KB so the file doesn't grow forever
###############################################################################

if [ -f "$LOG_FILE" ]; then
    size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt 204800 ]; then
        mv -f "$LOG_FILE" "${LOG_FILE}.bak"
    fi
fi

log_separator
log_msg "APEX Cleaner v1.3 started (post-fs-data stage)"
log_msg "KernelSU Next — Samsung One UI 7 / Android 14+"
log_separator

###############################################################################
# Boot attempt counter
# service.sh resets this to 0 on every successful boot.
# If we see >= BOOTLOOP_THRESHOLD here without a reset, we're bootlooping.
###############################################################################

# Read current count (default 0 if file absent or unreadable)
boot_count=0
if [ -f "$BOOTCOUNT_FILE" ]; then
    boot_count=$(cat "$BOOTCOUNT_FILE" 2>/dev/null | tr -d '[:space:]')
    # Validate it's a number
    case "$boot_count" in
        ''|*[!0-9]*) boot_count=0 ;;
    esac
fi

# Increment and save immediately so the count is persisted even if we crash
boot_count=$((boot_count + 1))
echo "$boot_count" > "$BOOTCOUNT_FILE"

log_msg "INFO: Boot attempt counter = $boot_count (threshold = $BOOTLOOP_THRESHOLD)"

###############################################################################
# BOOTLOOP MODE — wipe everything if we've exceeded the threshold
###############################################################################

if [ "$boot_count" -ge "$BOOTLOOP_THRESHOLD" ]; then

    log_separator
    log_msg "!!! BOOTLOOP DETECTED (attempt $boot_count) !!!"
    log_msg "Wiping ALL entries in $APEX_ACTIVE_DIR ..."
    log_separator

    wiped=0
    wipe_errors=0

    if [ -d "$APEX_ACTIVE_DIR" ]; then
        for entry in "$APEX_ACTIVE_DIR"/* "$APEX_ACTIVE_DIR"/.*; do
            case "$entry" in
                *"/." | *"/.." ) continue ;;
            esac
            [ -e "$entry" ] || [ -L "$entry" ] || continue

            name=$(basename "$entry")
            if rm -rf "$entry" 2>/dev/null; then
                log_msg "  WIPED: $name"
                wiped=$((wiped + 1))
            else
                log_msg "  ERROR: Could not wipe $name"
                wipe_errors=$((wipe_errors + 1))
            fi
        done
    else
        log_msg "  INFO: $APEX_ACTIVE_DIR does not exist — nothing to wipe."
    fi

    # Reset counter so the next boot is treated as fresh
    echo "0" > "$BOOTCOUNT_FILE"

    log_separator
    log_msg "BOOTLOOP RECOVERY DONE: $wiped wiped | $wipe_errors errors"
    log_msg "NOTE: Other KSU modules in /data/adb/modules/ were NOT touched."
    log_separator

    exit 0
fi

###############################################################################
# NORMAL MODE — targeted scan and selective removal of corrupted entries
###############################################################################

if [ ! -d "$APEX_ACTIVE_DIR" ]; then
    log_msg "INFO: $APEX_ACTIVE_DIR does not exist — nothing to do."
    log_msg "DONE: 0 deleted, 0 errors."
    exit 0
fi

# Count entries (glob produces literal '*' on empty dir)
entry_count=0
for _e in "$APEX_ACTIVE_DIR"/*; do
    [ -e "$_e" ] || [ -L "$_e" ] && entry_count=$((entry_count + 1))
done

if [ "$entry_count" -eq 0 ]; then
    log_msg "INFO: $APEX_ACTIVE_DIR is empty — nothing to do."
    log_msg "DONE: 0 deleted, 0 errors."
    exit 0
fi

log_msg "INFO: Found $entry_count entries in $APEX_ACTIVE_DIR (normal scan)"

###############################################################################
# Helper — validate a file as a zip/apex archive (magic bytes PK = 0x504B)
###############################################################################

is_valid_zip() {
    local file="$1"
    local size
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    [ "$size" -lt 4 ] && return 1
    local magic
    magic=$(dd if="$file" bs=1 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
    [ "$magic" = "504b" ] && return 0
    return 1
}

###############################################################################
# Helper — validate a directory-form APEX (Android 14+ decompressed APEXes)
# Must have apex_manifest.json OR apex_manifest.pb
###############################################################################

is_valid_apex_dir() {
    local dir="$1"
    [ -f "$dir/apex_manifest.json" ] && return 0
    [ -f "$dir/apex_manifest.pb" ]   && return 0
    return 1
}

###############################################################################
# Main scan loop
###############################################################################

cleaned=0
errors=0
ok_count=0

for entry in "$APEX_ACTIVE_DIR"/* "$APEX_ACTIVE_DIR"/.*; do

    case "$entry" in
        *"/." | *"/.." ) continue ;;
    esac

    [ -e "$entry" ] || [ -L "$entry" ] || continue

    name=$(basename "$entry")
    corrupted=false
    reason=""

    # ── Case 1: symlink (most common form in /data/apex/active) ─────────────
    if [ -L "$entry" ]; then
        target=$(readlink "$entry")
        resolved=$(readlink -f "$entry" 2>/dev/null)

        if [ -z "$resolved" ] || [ ! -e "$resolved" ]; then
            corrupted=true
            reason="broken symlink → '$target' (target missing or unresolvable)"

        elif [ -f "$resolved" ]; then
            if [ ! -s "$resolved" ]; then
                corrupted=true
                reason="symlink → zero-byte file at '$resolved'"
            elif ! is_valid_zip "$resolved"; then
                corrupted=true
                reason="symlink → file at '$resolved' has bad magic bytes (truncated apex)"
            fi

        elif [ -d "$resolved" ]; then
            if ! is_valid_apex_dir "$resolved"; then
                corrupted=true
                reason="symlink → dir '$resolved' missing apex_manifest.json/.pb"
            fi
        fi

    # ── Case 2: plain file directly in active/ ───────────────────────────────
    elif [ -f "$entry" ]; then
        if [ ! -s "$entry" ]; then
            corrupted=true
            reason="zero-byte file (not a valid apex archive)"
        elif ! is_valid_zip "$entry"; then
            corrupted=true
            reason="bad magic bytes (truncated or corrupted apex archive)"
        fi

    # ── Case 3: directory directly in active/ ────────────────────────────────
    elif [ -d "$entry" ]; then
        if ! is_valid_apex_dir "$entry"; then
            local_count=$(ls -1 "$entry" 2>/dev/null | wc -l)
            if [ "$local_count" -eq 0 ]; then
                corrupted=true
                reason="empty directory"
            else
                corrupted=true
                reason="directory missing apex_manifest.json/.pb ($local_count file(s) inside)"
            fi
        fi

    # ── Case 4: unexpected type (socket, device node, etc.) ──────────────────
    else
        corrupted=true
        reason="unexpected file type (not a file, directory, or symlink)"
    fi

    # ── Act on result ─────────────────────────────────────────────────────────
    if $corrupted; then
        log_msg "CORRUPTED [$name]: $reason"
        if rm -rf "$entry" 2>/dev/null; then
            log_msg "  → DELETED successfully"
            cleaned=$((cleaned + 1))
        else
            log_msg "  → ERROR: deletion failed"
            errors=$((errors + 1))
        fi
    else
        log_msg "OK        [$name]"
        ok_count=$((ok_count + 1))
    fi

done

log_separator
log_msg "DONE (normal scan): $ok_count healthy | $cleaned deleted | $errors errors"
log_separator

exit 0
