//! Real-Time Thread Priority
//!
//! Platform-specific thread priority elevation for audio processing.
//! Provides deterministic latency by prioritizing audio threads over
//! other system processes.
//!
//! # Platform Support
//!
//! - **macOS**: pthread QoS class (USER_INTERACTIVE) + real-time scheduling
//! - **Windows**: MMCSS (Multimedia Class Scheduler Service) "Pro Audio" class
//! - **Linux**: SCHED_FIFO with elevated priority (requires CAP_SYS_NICE or root)
//!
//! # Usage
//!
//! Call `set_realtime_priority()` at the start of your audio callback thread.
//! This should be done once when the audio stream starts, not on every callback.

use std::sync::atomic::{AtomicBool, Ordering};

/// Track if priority has been set (avoid repeated calls)
static PRIORITY_SET: AtomicBool = AtomicBool::new(false);

/// Result of priority elevation attempt
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PriorityResult {
    /// Successfully elevated to real-time priority
    Success,
    /// Already set (no action needed)
    AlreadySet,
    /// Failed to set priority (non-fatal, will use default)
    Failed,
    /// Platform not supported
    Unsupported,
}

/// Set real-time priority for the current thread.
///
/// This function is safe to call multiple times - it will only
/// attempt to set priority once per process.
///
/// # Returns
///
/// `PriorityResult` indicating the outcome.
pub fn set_realtime_priority() -> PriorityResult {
    if PRIORITY_SET.swap(true, Ordering::SeqCst) {
        return PriorityResult::AlreadySet;
    }

    let result = platform_set_priority();

    match result {
        PriorityResult::Success => {
            log::info!("Audio thread elevated to real-time priority");
        }
        PriorityResult::Failed => {
            log::warn!("Failed to set real-time thread priority (non-fatal)");
            PRIORITY_SET.store(false, Ordering::SeqCst); // Allow retry
        }
        PriorityResult::Unsupported => {
            log::debug!("Real-time priority not supported on this platform");
        }
        PriorityResult::AlreadySet => {}
    }

    result
}

/// Reset priority tracking (for testing)
#[doc(hidden)]
pub fn reset_priority_state() {
    PRIORITY_SET.store(false, Ordering::SeqCst);
}

// ═══════════════════════════════════════════════════════════════════════════════
// macOS Implementation
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(target_os = "macos")]
fn platform_set_priority() -> PriorityResult {
    use std::mem::MaybeUninit;

    // QOS_CLASS_USER_INTERACTIVE - highest non-realtime QoS
    const QOS_CLASS_USER_INTERACTIVE: u32 = 0x21;

    // Thread time constraint policy for true real-time
    #[repr(C)]
    struct ThreadTimeConstraintPolicy {
        period: u32,
        computation: u32,
        constraint: u32,
        preemptible: i32,
    }

    unsafe extern "C" {
        #[allow(dead_code)]
        fn pthread_self() -> libc::pthread_t;
        fn pthread_set_qos_class_self_np(qos_class: u32, relative_priority: i32) -> i32;
        fn mach_thread_self() -> u32;
        fn thread_policy_set(
            thread: u32,
            flavor: u32,
            policy_info: *const ThreadTimeConstraintPolicy,
            count: u32,
        ) -> i32;
    }

    // First, set QoS class for general high priority
    let qos_result = unsafe { pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) };

    if qos_result != 0 {
        log::debug!("pthread_set_qos_class_self_np failed: {}", qos_result);
        // Continue anyway - try real-time policy
    }

    // Set real-time thread time constraint policy
    // These values are tuned for audio processing:
    // - period: 1ms (1,000,000 ns) - typical audio callback interval
    // - computation: 500μs - time needed per callback
    // - constraint: 1ms - deadline
    const THREAD_TIME_CONSTRAINT_POLICY: u32 = 2;
    const THREAD_TIME_CONSTRAINT_POLICY_COUNT: u32 = 4;

    // Get mach timebase info for conversion
    #[repr(C)]
    struct MachTimebaseInfo {
        numer: u32,
        denom: u32,
    }

    unsafe extern "C" {
        fn mach_timebase_info(info: *mut MachTimebaseInfo) -> i32;
    }

    let mut timebase = MaybeUninit::<MachTimebaseInfo>::uninit();
    let timebase = unsafe {
        mach_timebase_info(timebase.as_mut_ptr());
        timebase.assume_init()
    };

    // Convert nanoseconds to mach absolute time
    let ns_to_abs =
        |ns: u64| -> u32 { ((ns * timebase.denom as u64) / timebase.numer as u64) as u32 };

    let policy = ThreadTimeConstraintPolicy {
        period: ns_to_abs(1_000_000),     // 1ms period
        computation: ns_to_abs(500_000),  // 500μs computation time
        constraint: ns_to_abs(1_000_000), // 1ms constraint (deadline)
        preemptible: 1,                   // Allow preemption if we exceed
    };

    let thread = unsafe { mach_thread_self() };
    let result = unsafe {
        thread_policy_set(
            thread,
            THREAD_TIME_CONSTRAINT_POLICY,
            &policy,
            THREAD_TIME_CONSTRAINT_POLICY_COUNT,
        )
    };

    if result == 0 {
        PriorityResult::Success
    } else {
        log::debug!("thread_policy_set failed: {} (QoS still applied)", result);
        // QoS was set, so partial success
        if qos_result == 0 {
            PriorityResult::Success
        } else {
            PriorityResult::Failed
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Windows Implementation
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(target_os = "windows")]
fn platform_set_priority() -> PriorityResult {
    use windows::Win32::Foundation::HANDLE;
    use windows::Win32::System::Threading::{
        AvSetMmThreadCharacteristicsW, GetCurrentThread, SetThreadPriority,
        THREAD_PRIORITY_TIME_CRITICAL,
    };
    use windows::core::PCWSTR;

    // First, try MMCSS (Multimedia Class Scheduler Service)
    // This is the preferred method for pro audio on Windows
    let task_name: Vec<u16> = "Pro Audio\0".encode_utf16().collect();
    let mut task_index: u32 = 0;

    let mmcss_handle =
        unsafe { AvSetMmThreadCharacteristicsW(PCWSTR(task_name.as_ptr()), &mut task_index) };

    if !mmcss_handle.is_invalid() {
        log::debug!(
            "MMCSS Pro Audio class registered (task index: {})",
            task_index
        );
        return PriorityResult::Success;
    }

    log::debug!("MMCSS registration failed, falling back to thread priority");

    // Fallback: Set thread priority directly
    let current_thread: HANDLE = unsafe { GetCurrentThread() };
    let result = unsafe { SetThreadPriority(current_thread, THREAD_PRIORITY_TIME_CRITICAL) };

    if result.as_bool() {
        PriorityResult::Success
    } else {
        PriorityResult::Failed
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Linux Implementation
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(target_os = "linux")]
fn platform_set_priority() -> PriorityResult {
    use libc::{
        SCHED_FIFO, SCHED_RR, pthread_self, pthread_setschedparam, sched_param, sched_setscheduler,
    };

    // Try SCHED_FIFO first (requires CAP_SYS_NICE or root)
    // Priority 80 is high but leaves room for kernel threads
    let mut param = sched_param { sched_priority: 80 };

    let result = unsafe { sched_setscheduler(0, SCHED_FIFO, &param) };

    if result == 0 {
        return PriorityResult::Success;
    }

    log::debug!("SCHED_FIFO failed (need CAP_SYS_NICE), trying SCHED_RR");

    // Try SCHED_RR as fallback (slightly less strict)
    param.sched_priority = 70;
    let result = unsafe { sched_setscheduler(0, SCHED_RR, &param) };

    if result == 0 {
        return PriorityResult::Success;
    }

    log::debug!("SCHED_RR failed, trying pthread_setschedparam");

    // Last resort: pthread_setschedparam (might work without root in some configs)
    param.sched_priority = 50;
    let thread = unsafe { pthread_self() };
    let result = unsafe { pthread_setschedparam(thread, SCHED_FIFO, &param) };

    if result == 0 {
        PriorityResult::Success
    } else {
        log::debug!("All Linux RT scheduling methods failed (errno: {})", result);
        PriorityResult::Failed
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Unsupported Platforms
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
fn platform_set_priority() -> PriorityResult {
    PriorityResult::Unsupported
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_set_priority_idempotent() {
        reset_priority_state();

        let first = set_realtime_priority();
        let second = set_realtime_priority();

        // Second call should return AlreadySet (if first succeeded)
        // or allow retry (if first failed)
        assert!(
            first == PriorityResult::Success
                || first == PriorityResult::Failed
                || first == PriorityResult::Unsupported
        );

        if first == PriorityResult::Success {
            assert_eq!(second, PriorityResult::AlreadySet);
        }

        reset_priority_state();
    }
}
