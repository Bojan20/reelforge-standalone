# Verification Protocol

## 1. Allocation Guard
Debug build must panic if heap allocation occurs in audio thread.

## 2. Lock Guard
Mutex / RwLock usage in audio thread must panic.

## 3. Processing Watchdog
Warn if processing time > 80%.
Log overrun if > 100%.

## 4. Stress Harness
Test:
- 512 channels
- 10 inserts each
- 10 sends each
- Automation active
- Solo spam
- Freeze spam
Run 10 minutes without overrun.

## 5. Memory Snapshot
No heap growth allowed after long session.
