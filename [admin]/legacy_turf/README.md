# legacy_turf

Admin event-zone resource for the Legacy ESX server. It is independent from the gang turf system in `op-crime`.

## Commands

- `/turfadmin` opens the management UI.
- `/startturf <zone id or exact name>` opens one saved zone.
- `/lockturf` snapshots the current participant roster and enables boundary enforcement.
- `/unlockturf` returns to Open and clears the old roster.
- `/stopturf` ends the event and clears all runtime state.

The `turf` permission is granted at aCore Level 4. Existing aCore duty rules still apply.

## Storage and restart behavior

The resource creates `legacy_turf_zones` automatically. `legacy_turf.sql` is included for manual provisioning. Saved zone definitions survive restarts, but the active event and roster intentionally do not.

## Runtime verification

For the first live load, run `refresh`, `restart aCore`, then `ensure legacy_turf`. On later updates, restart `aCore` before `legacy_turf`. Test Circle and Poly zones with one on-duty Level 4 admin and at least two member clients before using the lock flow in a live event.
