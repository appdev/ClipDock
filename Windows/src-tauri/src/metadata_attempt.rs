use std::{
    fs,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

static NEXT_ATTEMPT: AtomicU64 = AtomicU64::new(0);

/// Owns only this helper invocation's new files. There is no DB lease or worker
/// on Windows; the directory token prevents concurrent helpers overwriting one
/// another's returned assets, and dropped futures discard only their own files.
pub(super) struct MetadataAttempt {
    path: PathBuf,
    retained: bool,
}

impl MetadataAttempt {
    pub fn create(root: &Path) -> Result<Self, String> {
        let parent = root.join("metadata-attempts");
        fs::create_dir_all(&parent).map_err(|error| error.to_string())?;
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|error| error.to_string())?
            .as_nanos();
        for _ in 0..128 {
            let sequence = NEXT_ATTEMPT.fetch_add(1, Ordering::Relaxed);
            let path = parent.join(format!(
                "attempt-{}-{timestamp}-{sequence}",
                std::process::id()
            ));
            match fs::create_dir(&path) {
                Ok(()) => {
                    return Ok(Self {
                        path,
                        retained: false,
                    })
                }
                Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error.to_string()),
            }
        }
        Err("could not allocate metadata attempt directory".into())
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn retain(mut self) {
        self.retained = true;
    }
}

impl Drop for MetadataAttempt {
    fn drop(&mut self) {
        if !self.retained {
            let _ = fs::remove_dir_all(&self.path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancelled_or_late_attempt_only_removes_its_own_files() {
        let directory = tempfile::tempdir().unwrap();
        let older = MetadataAttempt::create(directory.path()).unwrap();
        let newer = MetadataAttempt::create(directory.path()).unwrap();
        assert_ne!(older.path(), newer.path());
        let old_path = older.path().join("icon.png");
        let new_path = newer.path().join("icon.png");
        fs::write(&old_path, b"older fixture").unwrap();
        fs::write(&new_path, b"newer fixture").unwrap();
        newer.retain();
        drop(older);
        assert!(!old_path.exists());
        assert_eq!(fs::read(new_path).unwrap(), b"newer fixture");
    }
}
