#!/system/bin/sh
# service.sh
# Runs after the system has fully booted (late-start service stage).
#
# Key job: reset the bootloop counter so the next shutdown/reboot is treated
# as a fresh start and doesn't trigger bootloop-wipe mode unnecessarily.

MODDIR=${0%/*}
LOG_FILE="/data/local/tmp/apex_cleaner.log"
BOOTCOUNT_FILE="$MODDIR/bootcount"
APEX_ACTIVE_DIR="/data/apex/active"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Give the system time to fully stabilise before we declare success
# (waits for sys.boot_completed=1 or times out after 60 s)
boot_wait=0
while [ "$boot_wait" -lt 60 ]; do
    completed=$(getprop sys.boot_completed 2>/dev/null)
    [ "$completed" = "1" ] && break
    sleep 2
    boot_wait=$((boot_wait + 2))
done

if [ "$boot_wait" -ge 60 ]; then
    log_msg "WARN (service): sys.boot_completed never became 1 within 60 s — not resetting counter."
    exit 0
fi

# ── Successful boot confirmed ────────────────────────────────────────────────

log_msg "INFO: Boot completed successfully (sys.boot_completed=1)."
log_msg "INFO: Resetting bootloop counter to 0."
echo "0" > "$BOOTCOUNT_FILE"

# ── Post-boot dangling-symlink scan (informational only) ─────────────────────
# We cannot safely remove them without a reboot at this point, but we log
# them so the user can see what (if anything) slipped through early boot.

if [ -d "$APEX_ACTIVE_DIR" ]; then
    warn_count=0
    for entry in "$APEX_ACTIVE_DIR"/*; do
        [ -L "$entry" ] || continue
        resolved=$(readlink -f "$entry" 2>/dev/null)
        if [ -z "$resolved" ] || [ ! -e "$resolved" ]; then
            log_msg "WARN (post-boot): Dangling symlink still present: $(basename "$entry") → $(readlink "$entry")"
            warn_count=$((warn_count + 1))
        fi
    done
    if [ "$warn_count" -eq 0 ]; then
        log_msg "INFO: No dangling symlinks found in $APEX_ACTIVE_DIR post-boot."
    fi
fi

log_msg "INFO: APEX Cleaner service check complete."

exit 0
