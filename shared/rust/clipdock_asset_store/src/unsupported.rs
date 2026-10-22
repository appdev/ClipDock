//! Windows keeps its existing native writer until native no-follow validation.
use std::{fs::File, io, path::Path};
pub(crate) struct Directory;
fn unavailable<T>() -> io::Result<T> {
    Err(io::Error::new(
        io::ErrorKind::Unsupported,
        "managed asset writer requires platform validation",
    ))
}
impl Directory {
    pub fn open(_: &Path) -> io::Result<Self> {
        unavailable()
    }
    pub fn open_lock(&self, _: &str) -> io::Result<File> {
        unavailable()
    }
    pub fn create_new(&self, _: &str) -> io::Result<File> {
        unavailable()
    }
    pub fn read(&self, _: &str) -> io::Result<File> {
        unavailable()
    }
    pub fn read_write(&self, _: &str) -> io::Result<File> {
        unavailable()
    }
    pub fn rename(&self, _: &str, _: &str) -> io::Result<()> {
        unavailable()
    }
    pub fn replace(&self, _: &str, _: &str) -> io::Result<()> {
        unavailable()
    }
    pub fn delete(&self, _: &str) -> io::Result<Option<u64>> {
        unavailable()
    }
    pub fn files(&self, _: &str) -> io::Result<Vec<String>> {
        unavailable()
    }
}
