//! Secure credential storage abstraction.
//!
//! Default implementation uses the OS keychain (`keyring` crate):
//! - macOS: Keychain Services
//! - Windows: Credential Manager
//! - Linux: Secret Service (GNOME Keyring / KWallet)
//!
//! All credentials are stored under the service name `com.vanvinkl.fluxforge.composer`
//! with per-provider account names (`anthropic`, `azure_openai`).
//!
//! ## Why an abstraction?
//!
//! Tests must NOT touch the real OS keychain (CI machines have no unlocked keychain,
//! and parallel tests would race). The trait lets us swap in `MemoryStore` for tests.

use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;

const SERVICE_NAME: &str = "com.vanvinkl.fluxforge.composer";

/// All errors that credential storage can produce.
#[derive(Error, Debug)]
pub enum CredentialError {
    /// No credential found for the requested account.
    #[error("credential not found for account '{0}'")]
    NotFound(String),

    /// OS keychain rejected access (locked, denied, no entitlement).
    #[error("keychain access denied: {0}")]
    AccessDenied(String),

    /// Keychain backend error.
    #[error("keychain error: {0}")]
    Backend(String),
}

/// Result alias for credential operations.
pub type CredentialResult<T> = Result<T, CredentialError>;

/// Trait for credential storage backends.
///
/// Implementations must be `Send + Sync` so they can be shared across tasks.
pub trait CredentialStore: Send + Sync {
    /// Store a secret (overwrites any existing value for that account).
    fn put(&self, account: &str, secret: &str) -> CredentialResult<()>;

    /// Retrieve a secret. Returns `NotFound` if no entry exists.
    fn get(&self, account: &str) -> CredentialResult<String>;

    /// Delete a secret. Returns `Ok(())` even if the entry didn't exist (idempotent).
    fn delete(&self, account: &str) -> CredentialResult<()>;

    /// Check whether an account has a secret stored (without fetching it).
    fn exists(&self, account: &str) -> bool {
        self.get(account).is_ok()
    }
}

// ─── OS Keychain backend ──────────────────────────────────────────────────────

/// Production credential store backed by the OS keychain.
pub struct KeychainStore {
    service: String,
}

impl KeychainStore {
    /// Create a store using the default FluxForge service name.
    pub fn new() -> Self {
        Self {
            service: SERVICE_NAME.to_string(),
        }
    }

    /// Create a store with a custom service name (useful for tests / multi-tenant).
    pub fn with_service(service: impl Into<String>) -> Self {
        Self {
            service: service.into(),
        }
    }
}

impl Default for KeychainStore {
    fn default() -> Self {
        Self::new()
    }
}

impl CredentialStore for KeychainStore {
    fn put(&self, account: &str, secret: &str) -> CredentialResult<()> {
        let entry = keyring::Entry::new(&self.service, account)
            .map_err(|e| CredentialError::Backend(e.to_string()))?;
        entry
            .set_password(secret)
            .map_err(|e| match e {
                keyring::Error::NoEntry => CredentialError::NotFound(account.to_string()),
                keyring::Error::PlatformFailure(_) => CredentialError::AccessDenied(e.to_string()),
                _ => CredentialError::Backend(e.to_string()),
            })
    }

    fn get(&self, account: &str) -> CredentialResult<String> {
        let entry = keyring::Entry::new(&self.service, account)
            .map_err(|e| CredentialError::Backend(e.to_string()))?;
        entry.get_password().map_err(|e| match e {
            keyring::Error::NoEntry => CredentialError::NotFound(account.to_string()),
            keyring::Error::PlatformFailure(_) => CredentialError::AccessDenied(e.to_string()),
            _ => CredentialError::Backend(e.to_string()),
        })
    }

    fn delete(&self, account: &str) -> CredentialResult<()> {
        let entry = keyring::Entry::new(&self.service, account)
            .map_err(|e| CredentialError::Backend(e.to_string()))?;
        match entry.delete_credential() {
            Ok(()) => Ok(()),
            // Idempotent — deleting a nonexistent entry is success.
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(CredentialError::Backend(e.to_string())),
        }
    }
}

// ─── In-memory backend (tests, ephemeral runs) ────────────────────────────────

/// In-memory credential store for tests and ephemeral / privacy-mode operation.
///
/// Secrets are wiped when the store is dropped — never persisted to disk.
#[derive(Default, Clone)]
pub struct MemoryStore {
    inner: Arc<Mutex<HashMap<String, String>>>,
}

impl MemoryStore {
    /// Create a fresh empty in-memory store.
    pub fn new() -> Self {
        Self::default()
    }
}

impl CredentialStore for MemoryStore {
    fn put(&self, account: &str, secret: &str) -> CredentialResult<()> {
        self.inner
            .lock()
            .insert(account.to_string(), secret.to_string());
        Ok(())
    }

    fn get(&self, account: &str) -> CredentialResult<String> {
        self.inner
            .lock()
            .get(account)
            .cloned()
            .ok_or_else(|| CredentialError::NotFound(account.to_string()))
    }

    fn delete(&self, account: &str) -> CredentialResult<()> {
        self.inner.lock().remove(account);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn memory_store_put_get_round_trip() {
        let store = MemoryStore::new();
        store.put("anthropic", "sk-test-1234").unwrap();
        assert_eq!(store.get("anthropic").unwrap(), "sk-test-1234");
    }

    #[test]
    fn memory_store_get_missing_returns_not_found() {
        let store = MemoryStore::new();
        match store.get("missing") {
            Err(CredentialError::NotFound(name)) => assert_eq!(name, "missing"),
            other => panic!("expected NotFound, got {:?}", other),
        }
    }

    #[test]
    fn memory_store_delete_is_idempotent() {
        let store = MemoryStore::new();
        store.delete("never_existed").unwrap();
        store.put("temp", "v").unwrap();
        store.delete("temp").unwrap();
        store.delete("temp").unwrap(); // second delete must succeed
        assert!(!store.exists("temp"));
    }

    #[test]
    fn memory_store_exists_check() {
        let store = MemoryStore::new();
        assert!(!store.exists("a"));
        store.put("a", "x").unwrap();
        assert!(store.exists("a"));
    }

    #[test]
    fn memory_store_overwrite() {
        let store = MemoryStore::new();
        store.put("k", "v1").unwrap();
        store.put("k", "v2").unwrap();
        assert_eq!(store.get("k").unwrap(), "v2");
    }

    #[test]
    fn memory_store_concurrent_safe() {
        use std::thread;
        let store = MemoryStore::new();
        let mut handles = Vec::new();
        for i in 0..10 {
            let s = store.clone();
            handles.push(thread::spawn(move || {
                s.put(&format!("k{}", i), &format!("v{}", i)).unwrap();
            }));
        }
        for h in handles {
            h.join().unwrap();
        }
        for i in 0..10 {
            assert_eq!(store.get(&format!("k{}", i)).unwrap(), format!("v{}", i));
        }
    }
}
