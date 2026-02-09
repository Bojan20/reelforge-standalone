use std::collections::HashMap;
/// Sidechain Routing FFI (P0.5)
use std::ffi::c_int;
use std::sync::Mutex;

// Global sidechain routing storage (track_id, slot) -> source_track_id
static SIDECHAIN_MAP: Mutex<Option<HashMap<(u64, u64), i64>>> = Mutex::new(None);

fn get_map() -> &'static Mutex<Option<HashMap<(u64, u64), i64>>> {
    &SIDECHAIN_MAP
}

#[unsafe(no_mangle)]
pub extern "C" fn insert_set_sidechain_source(
    track_id: u64,
    slot_index: u64,
    source_track_id: i64,
) -> c_int {
    if slot_index >= 8 {
        return -1;
    }
    if source_track_id < -1 || source_track_id >= 1024 {
        return -1;
    }

    let mut map_lock = get_map().lock().unwrap();
    if map_lock.is_none() {
        *map_lock = Some(HashMap::new());
    }

    if let Some(ref mut map) = *map_lock {
        map.insert((track_id, slot_index), source_track_id);
    }

    0
}

#[unsafe(no_mangle)]
pub extern "C" fn insert_get_sidechain_source(track_id: u64, slot_index: u64) -> i64 {
    if slot_index >= 8 {
        return -2;
    }

    let map_lock = get_map().lock().unwrap();
    if let Some(ref map) = *map_lock {
        return *map.get(&(track_id, slot_index)).unwrap_or(&-1);
    }

    -1
}

#[unsafe(no_mangle)]
pub extern "C" fn insert_set_sidechain_enabled(
    _track_id: u64,
    slot_index: u64,
    _enabled: c_int,
) -> c_int {
    if slot_index >= 8 {
        return -1;
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sidechain_set_get() {
        let result = insert_set_sidechain_source(0, 0, 5);
        assert_eq!(result, 0);

        let source = insert_get_sidechain_source(0, 0);
        assert_eq!(source, 5);
    }

    #[test]
    fn test_sidechain_disable() {
        insert_set_sidechain_source(1, 1, -1);
        let source = insert_get_sidechain_source(1, 1);
        assert_eq!(source, -1);
    }
}
