# Daily timer plan for Kids Mode

## Goal

Add a `daily_timer` setting to Kids Mode so the play timer can either:

- behave as the current session-based timer, or
- behave as a daily timer that resets at local midnight.

The expected UX is:

- default remains current behavior (`daily_timer: false`)
- when enabled, the timer is a daily budget
- the timer picks a total daily allowance (for example 5-120 minutes in 5-minute increments)
- when the parent adds extra time, that extra time is added to the current day’s budget without changing the configured daily cap
- on the next local midnight, the daily allowance resets automatically

## Configuration

Add a setting to `App/KidsMode/kidmode.json`:

```json
{
  "pin_hash": "",
  "pin_salt": "",
  "pin_plain": "",
  "lock_retroarch_hotkeys": true,
  "daily_timer": false
}
```

Notes:
- Keep the default as `false` to preserve current behavior.
- This is a config-backed mode switch, not a runtime-only toggle.

## Code change breakdown

### 1. Update timer state handling in `App/KidsMode/kid_mode_loop.sh`

Current state file: `Saves/kidmode/timer_state.txt`

It already stores:
- day
- used seconds
- bonus seconds

We need to add a daily reset check before computing remaining time.

Implementation tasks:
- read the saved `day` from `timer_state.txt`
- compare it with `date +%Y-%m-%d`
- if `daily_timer` is enabled and the day changed:
  - set used = 0
  - optionally keep or clear bonus depending on desired semantics
  - reset the rolling budget for the new day
- ensure this happens before `update_remaining_now()` and before the ticker loop writes the remaining time

Important decision:
- `bonus` should not permanently change the configured daily limit
- add-time should increase the current-day allocation but should not mutate the daily config itself
- the daily reset should clear the daily accumulated usage and any daily bonus for the new day

### 2. Update timer budget math

In `update_remaining_now()`:
- current budget = configured timer minutes + bonus
- remaining = budget - used

For `daily_timer: true`, the logic should work as follows:
- on a new day, reset the usage for that date
- the current daily value is evaluated from the configured daily amount
- extra time added from the parent menu is treated as extra current-day allowance only

Behavioral rules:
- session mode: current behavior remains unchanged
- daily mode: timer resets at local midnight, independent of the session lifecycle
- add-time does not alter the base daily timer value used on future days

### 3. Add the UI toggle in the timer setup flow

File: `src/kidsMode/kidui.c`

The timer setup flow already has the picker for menu time selection.
We need a checkbox-style control for the setup prompt, represented as something like:
- `Refresh every day` / `Daily timer`
- On = enable `daily_timer`
- Off = normal session mode

User interface behavior:
- when arming, the parent can choose the timer length and whether the timer refreshes every day
- the option is persisted to `kidmode.json`
- the timer selection still uses the current 5-minute step system

This should be added to the same screen or adjacent entry as the timer picker, without redesigning the whole flow.

### 4. Add parent-menu support for daily timer mode

The parent menu already includes:
- add play time
- turn off timer
- change brightness
- auto resume
- change PIN

We should add a runtime or session setting to toggle the daily refresh behavior in the parent menu as well, so users can change it without re-arming.

Suggested row names:
- `Daily timer: Off`
- `Daily timer: On`

The implementation should:
- update the config file
- immediately affect future remaining budgets
- not alter the already picked base daily amount unless the user deliberately changes it

### 5. Preserve the add-time semantics

Behavior requirement:
- When the parent adds extra time, it applies only to the current day.
- The configured daily timer value does not change.

In shell terms:
- `state_bonus` should be added to the current day’s budget
- it should not rewrite the default `daily_timer` setting
- it should be wiped when the date changes in daily mode

### 6. Update docs and help text

File: `README.md`

Add documentation for:
- the new `daily_timer` config key
- the timer checkbox / toggle wording in the UI
- reset-at-midnight behavior
- the add-time semantics

### 7. Build and validation plan

No code changes yet in this branch. The first step is to ensure the app builds successfully in the baseline project state.

Validation to run after implementation:
- build `src/kidsMode/kidui.c` in the Onion toolchain
- enable daily timer and confirm the timer resets at midnight
- verify session mode behaves exactly as before
- verify extra time adds to the current day only
- verify the timer value remains correct after a reboot
- verify no regressions to the parent unlock flow or PIN flow

## Execution order

1. Baseline check: build the app as-is and confirm it works
2. Add config key + timer-mode handling in `kid_mode_loop.sh`
3. Update timer setup UI in `kidui.c`
4. Add parent-menu toggle if needed
5. Update docs and comments
6. Run targeted validation and record results

## Acceptance criteria

- `daily_timer` defaults to `false`
- the app still behaves like the current session timer when off
- when enabled, the timer resets at local midnight
- parent add-time increases the current day only
- the configured daily timer value is not overwritten by add-time
- the build still succeeds without regressions
