# APEX Active Cleaner

A root module for Android that automatically detects and removes corrupted entries from `/data/apex/active` at early boot — preventing bootloops caused by dirty shutdowns on custom ROMs.

Tested on **Samsung Galaxy S9+** and **S10+** running custom ROMs based on the S24 FE (One UI 7 / Android 14+).

---

## Features

- **Early-boot corruption scan** — runs before Android tries to mount APEX packages, so corrupted entries are gone before they can cause a bootloop
- **Bootloop guard** — tracks consecutive failed boot attempts; if the phone fails to boot 3 times in a row, it wipes all of `/data/apex/active` automatically
- **Safe by design** — only touches `/data/apex/active`; never modifies other modules, system partitions, or `/data/apex/decompressed/`
- **Detailed logging** — every action (scan result, deletion, wipe, boot success) is timestamped and written to `/data/local/tmp/apex_cleaner.log`
- **Log rotation** — log file is capped at 200 KB with automatic rollover to a `.bak` file

---

## Compatibility

| Root Framework | Compatible |
|---|---|
| KernelSU Next | ✅ Yes (primary target) |
| KernelSU (official) | ✅ Yes |
| Magisk (stable / delta / alpha) | ✅ Yes |
| APatch | ✅ Yes |

**Android version:** Android 13 and above (tested on Android 15 / One UI 7)

**Architecture:** Any (the module is pure shell script — no native binaries)

---

## How It Works

### Stage 1 — Normal boot (corruption scan)

On every boot, `post-fs-data.sh` runs in the early `post-fs-data` stage, before `apexd` (the APEX mounting daemon) has a chance to read the directory. It scans every entry in `/data/apex/active` and removes anything that matches a corruption pattern:

| Corruption type | Detection method |
|---|---|
| Broken symlink | `readlink -f` returns empty or points to a missing path |
| Symlink → zero-byte file | File exists but has 0 bytes |
| Symlink → truncated apex | File exists but magic bytes are not `PK` (0x504B) |
| Zero-byte regular file | File present but empty |
| Truncated regular file | File present but fails magic-byte check |
| Empty directory | Directory has 0 children |
| Directory missing manifest | No `apex_manifest.json` or `apex_manifest.pb` found |
| Unexpected file type | Socket, device node, or anything that isn't a file/dir/symlink |

Healthy entries are left completely untouched.

### Stage 2 — Bootloop recovery (full wipe)

The module keeps a counter in `$MODDIR/bootcount` (inside the module's own directory at `/data/adb/modules/apex_cleaner/bootcount`).

- `post-fs-data.sh` increments the counter on every boot attempt
- `service.sh` resets the counter to `0` once `sys.boot_completed=1` is confirmed

If the counter reaches **3** (meaning 3 consecutive boots that never completed), the module switches to recovery mode and wipes **everything** inside `/data/apex/active`, then resets the counter. The next boot starts with a clean directory.

**Nothing outside `/data/apex/active` is modified during a wipe.** Your other modules, app data, and system files are not affected.

---

## Installation

1. Download the latest `.zip` from [Releases](https://github.com/sofikuw/Apex-Cleaner/releases)
2. Open your root manager (KernelSU Next / Magisk / APatch)
3. Go to **Modules → Install from storage**
4. Select the downloaded zip
5. Reboot

The module is active immediately on the next boot. No configuration needed.

---

## Reading the Log

Open a terminal app or ADB shell and run:

```sh
cat /data/local/tmp/apex_cleaner.log
```

### Normal boot (no corruption)

```
================================================================================
[2025-03-30 08:12:01] APEX Cleaner v1.3 started (post-fs-data stage)
[2025-03-30 08:12:01] INFO: Boot attempt counter = 1 (threshold = 3)
[2025-03-30 08:12:01] INFO: Found 12 entries in /data/apex/active (normal scan)
[2025-03-30 08:12:01] OK        [com.android.adbd]
[2025-03-30 08:12:01] OK        [com.android.art]
...
[2025-03-30 08:12:03] DONE (normal scan): 12 healthy | 0 deleted | 0 errors
================================================================================
[2025-03-30 08:12:55] INFO: Boot completed successfully (sys.boot_completed=1).
[2025-03-30 08:12:55] INFO: Resetting bootloop counter to 0.
```

### Normal boot (corruption found and removed)

```
[2025-03-30 08:12:02] CORRUPTED [com.android.foo]: broken symlink → '../decompressed/com.android.foo' (target missing or unresolvable)
[2025-03-30 08:12:02]   → DELETED successfully
```

### Bootloop recovery

```
================================================================================
!!! BOOTLOOP DETECTED (attempt 3) !!!
Wiping ALL entries in /data/apex/active ...
================================================================================
[2025-03-30 08:12:01]   WIPED: com.android.adbd
[2025-03-30 08:12:01]   WIPED: com.android.art
...
[2025-03-30 08:12:02] BOOTLOOP RECOVERY DONE: 14 wiped | 0 errors
[2025-03-30 08:12:02] NOTE: Other KSU modules in /data/adb/modules/ were NOT touched.
================================================================================
```

---

## File Structure

```
apex-cleaner/
├── META-INF/
│   └── com/google/android/
│       ├── update-binary       # Module installer entry point
│       └── updater-script      # Required by Magisk-format flasher
├── module.prop                 # Module metadata (id, name, version)
├── customize.sh                # Runs during flash — sets permissions
├── post-fs-data.sh             # Early-boot hook — corruption scan + bootloop guard
└── service.sh                  # Late-boot hook — resets bootloop counter on success
```

**Runtime files created on device:**

| Path | Purpose |
|---|---|
| `/data/adb/modules/apex_cleaner/bootcount` | Persistent boot attempt counter |
| `/data/local/tmp/apex_cleaner.log` | Main log (current session) |
| `/data/local/tmp/apex_cleaner.log.bak` | Previous log (after rotation) |

---

## Background / Why This Exists

On Samsung devices running custom ROMs that port One UI 7 to older hardware (S9+, S10+), the ROM's shutdown sequence can occasionally fail to cleanly unmount APEX packages. When the device powers off mid-unmount, entries in `/data/apex/active` can be left as broken symlinks, empty files, or truncated archives. On the next boot, `apexd` tries to mount these and fails — causing a bootloop.

The standard fix is to boot into recovery, mount `/data`, and manually delete the bad entries. This module automates that process entirely without requiring recovery access.

---

## Changelog

### v1.0
- Initial release
- Early-boot scan covering: broken symlinks, zero-byte files, truncated archives, empty dirs, missing APEX manifests
- Bootloop detection and automatic full-wipe recovery after 3 consecutive failed boots
- Boot attempt counter stored in module directory (`bootcount` file), isolated from other modules
- `service.sh` now waits for `sys.boot_completed=1` before resetting counter (more reliable than a fixed sleep)

---

## License

MIT License — free to use, modify, and distribute. Attribution appreciated but not required.
