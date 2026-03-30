#!/system/bin/sh
# customize.sh — installer script, runs during flash via KernelSU Manager

ui_print ""
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "   APEX Active Cleaner  v1"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print ""
ui_print "• Installs post-fs-data hook for early boot"
ui_print "• Detects corrupted /data/apex/active entries"
ui_print "• Deletes broken symlinks, empty dirs, bad apex files"
ui_print "• Bootloop guard: wipes /data/apex/active after"
ui_print "  3 consecutive failed boots (other modules safe)"
ui_print "• Logs all actions to:"
ui_print "    /data/local/tmp/apex_cleaner.log"
ui_print ""

# Ensure scripts are executable
set_perm "$MODPATH/post-fs-data.sh" root root 0755 0755
set_perm "$MODPATH/service.sh"      root root 0755 0755

# Create log dir if it doesn't exist yet
mkdir -p /data/local/tmp 2>/dev/null
chmod 777 /data/local/tmp 2>/dev/null

ui_print "• Installation complete!"
ui_print ""
ui_print "  Reboot your device. If /data/apex/active has"
ui_print "  corrupted entries, they will be removed before"
ui_print "  Android tries to mount them."
ui_print ""
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
