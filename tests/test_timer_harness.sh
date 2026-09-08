#!/bin/bash
set -euo pipefail

# Small harness to test timer logic (isolated, doesn't touch /mnt)
ROOT="$PWD/.test_kidmode"
mkdir -p "$ROOT"
backupdir="$ROOT"
configfile="$ROOT/kidmode.json"
timer_state="$backupdir/timer_state.txt"
remaining_file="$ROOT/kidmode_remaining"

# Minimal jq-based config helpers (same semantics as kid_mode_loop.sh)
config_merge() {
    ensure_config
    tmpcfg=$(mktemp)
    jq "$@" "$configfile" > "$tmpcfg" && mv -f "$tmpcfg" "$configfile"
}

config_get() {
    [ -f "$configfile" ] || return 1
    jq -r "(.\"$1\" // empty) | tostring" "$configfile"
}

ensure_config() {
    if [ ! -f "$configfile" ] || ! jq -e . "$configfile" > /dev/null 2>&1; then
        printf '{\n    "pin_hash": "",\n    "pin_salt": "",\n    "pin_plain": ""\n}\n' > "$configfile"
    fi
}

# timer state: 3 lines: day / used seconds / bonus seconds
state_read() {
    st_day=""
    st_used=0
    st_bonus=0
    [ -f "$timer_state" ] || return 0
    {
        IFS= read -r st_day || true
        IFS= read -r st_used || true
        IFS= read -r st_bonus || true
    } < "$timer_state"
    case "$st_used" in '' | *[!0-9]*) st_used=0 ;; esac
    case "$st_bonus" in '' | *[!0-9]*) st_bonus=0 ;; esac
}

state_write() {
    mkdir -p "$backupdir"
    printf '%s\n%s\n%s\n' "$(date +%Y-%m-%d)" "$1" "$2" > "$timer_state.tmp"
    mv -f "$timer_state.tmp" "$timer_state"
}

state_day() { state_read; printf '%s\n' "$st_day"; }
state_used() { state_read; printf '%s\n' "$st_used"; }
state_bonus() { state_read; printf '%s\n' "$st_bonus"; }

get_timer_minutes() {
    tm="$(config_get timer_minutes)"
    case "$tm" in
        '' | *[!0-9]*) echo 0 ;;
        *) echo "$tm" ;;
    esac
}

# daily timer config helpers
get_daily_timer() {
    v="$(config_get daily_timer)"
    case "$v" in
        true|1|yes|on) echo 1 ;;
        *) echo 0 ;;
    esac
}
set_daily_timer() {
    case "$1" in
        1|true|TRUE|yes|on)
            config_merge '.daily_timer = true'
            ;;
        *)
            config_merge '.daily_timer = false'
            ;;
    esac
}

# Reset at midnight if daily mode enabled
daily_state_reset_if_needed() {
    [ "$(get_daily_timer)" = "1" ] || return 0
    today="$(date +%Y-%m-%d)"
    state_read
    if [ -n "$st_day" ] && [ "$st_day" != "$today" ]; then
        state_write 0 0
        echo "daily reset: $today"
    fi
}

update_remaining_now() {
    daily_state_reset_if_needed
    budget=$(($(get_timer_minutes) * 60 + $(state_bonus)))
    if [ "$budget" -le 0 ]; then
        rm -f "$remaining_file"
        return 0
    fi
    rem=$((budget - $(state_used)))
    [ "$rem" -lt 0 ] && rem=0
    echo "$rem" > "$remaining_file"
}

timer_remaining() {
    update_remaining_now
    if [ -f "$remaining_file" ]; then
        cat "$remaining_file"
    else
        echo -1
    fi
}

add_bonus() {
    state_read
    newbonus=$((st_bonus + $1))
    state_write "$st_used" "$newbonus"
    update_remaining_now
}

# Start tests
rm -f "$configfile" "$timer_state" "$remaining_file"
ensure_config

printf '\n=== Test 1: session mode behaves as before ===\n'
config_merge '.timer_minutes = 30'
set_daily_timer 0
state_write 0 0
update_remaining_now
echo "remaining (sec)=$(cat $remaining_file) expected=1800"

printf '\n=== Test 2: add bonus increases remaining but not base minutes ===\n'
add_bonus 300
echo "remaining after bonus (sec)=$(cat $remaining_file) expected=2100"
if [ "$(config_get timer_minutes)" != "30" ]; then echo "ERROR: base timer changed"; exit 1; fi

printf '\n=== Test 3: daily mode resets at date change ===\n'
config_merge '.timer_minutes = 60'
set_daily_timer 1
# simulate that state file shows yesterday used 1800
printf '%s\n%s\n%s\n' "$(date -d 'yesterday' +%Y-%m-%d)" "1800" "0" > "$timer_state"
# now call update_remaining_now -> should trigger daily reset
rem1=$(timer_remaining)
echo "remaining after rollover (sec)=$rem1 expected=3600"

printf '\n=== Test 4: add bonus in daily mode only affects today ===\n'
add_bonus 600
echo "remaining after bonus (sec)=$(cat $remaining_file) expected=4200"

printf '\nAll tests complete. Files in: %s\n' "$ROOT"
exit 0
