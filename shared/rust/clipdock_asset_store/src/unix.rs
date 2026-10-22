use std::ffi::{CStr, CString};
use std::fs::File;
use std::io;
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

pub(crate) struct Directory {
    root: File,
}
fn name(value: &str) -> io::Result<CString> {
    CString::new(value).map_err(|_| super::invalid("NUL in asset component"))
}
fn opened(fd: libc::c_int) -> io::Result<File> {
    if fd < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(unsafe { File::from_raw_fd(fd) })
    }
}
fn open_directory(parent: &File, child: &str, create: bool) -> io::Result<File> {
    let child = name(child)?;
    let flags = libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC;
    let mut fd = unsafe { libc::openat(parent.as_raw_fd(), child.as_ptr(), flags) };
    if fd < 0 && create && io::Error::last_os_error().kind() == io::ErrorKind::NotFound {
        let result = unsafe { libc::mkdirat(parent.as_raw_fd(), child.as_ptr(), 0o700) };
        if result < 0 && io::Error::last_os_error().kind() != io::ErrorKind::AlreadyExists {
            return Err(io::Error::last_os_error());
        }
        fd = unsafe { libc::openat(parent.as_raw_fd(), child.as_ptr(), flags) };
    }
    opened(fd)
}
impl Directory {
    pub fn open(root: &Path) -> io::Result<Self> {
        std::fs::create_dir_all(root)?;
        if std::fs::symlink_metadata(root)?.file_type().is_symlink() {
            return Err(super::invalid("asset root cannot be a symlink"));
        }
        let root = CString::new(root.as_os_str().as_bytes())
            .map_err(|_| super::invalid("NUL in asset root"))?;
        let fd = unsafe {
            libc::open(
                root.as_ptr(),
                libc::O_RDONLY | libc::O_DIRECTORY | libc::O_NOFOLLOW | libc::O_CLOEXEC,
            )
        };
        Ok(Self { root: opened(fd)? })
    }
    fn parent(&self, path: &str, create: bool) -> io::Result<(File, CString)> {
        if path.contains(['\\', ':', '\0'])
            || path
                .split('/')
                .any(|p| p.is_empty() || p == "." || p == "..")
        {
            return Err(super::invalid("invalid controlled path"));
        }
        let mut parts = path.split('/').collect::<Vec<_>>();
        let leaf = name(
            parts
                .pop()
                .ok_or_else(|| super::invalid("empty asset path"))?,
        )?;
        let mut directory = self.root.try_clone()?;
        for part in parts {
            directory = open_directory(&directory, part, create)?;
        }
        Ok((directory, leaf))
    }
    fn open_file(&self, path: &str, flags: i32, create_parents: bool) -> io::Result<File> {
        let (parent, leaf) = self.parent(path, create_parents)?;
        let file = opened(unsafe {
            libc::openat(
                parent.as_raw_fd(),
                leaf.as_ptr(),
                flags | libc::O_NOFOLLOW | libc::O_CLOEXEC | libc::O_NONBLOCK,
                0o600,
            )
        })?;
        if !file.metadata()?.is_file() {
            return Err(super::invalid("managed asset is not a regular file"));
        }
        Ok(file)
    }
    pub fn open_lock(&self, path: &str) -> io::Result<File> {
        self.open_file(path, libc::O_RDWR | libc::O_CREAT, true)
    }
    pub fn create_new(&self, path: &str) -> io::Result<File> {
        self.open_file(path, libc::O_WRONLY | libc::O_CREAT | libc::O_EXCL, true)
    }
    pub fn read(&self, path: &str) -> io::Result<File> {
        self.open_file(path, libc::O_RDONLY, false)
    }
    pub fn read_write(&self, path: &str) -> io::Result<File> {
        self.open_file(path, libc::O_RDWR, false)
    }
    pub fn rename(&self, from: &str, to: &str) -> io::Result<()> {
        // Open source with no-follow before moving; directories are fd-anchored.
        self.read(from)?;
        let (source, from) = self.parent(from, false)?;
        let (destination, to) = self.parent(to, true)?;
        #[cfg(target_os = "macos")]
        let result = unsafe {
            libc::renameatx_np(
                source.as_raw_fd(),
                from.as_ptr(),
                destination.as_raw_fd(),
                to.as_ptr(),
                libc::RENAME_EXCL,
            )
        };
        #[cfg(target_os = "linux")]
        let result = unsafe {
            libc::renameat2(
                source.as_raw_fd(),
                from.as_ptr(),
                destination.as_raw_fd(),
                to.as_ptr(),
                libc::RENAME_NOREPLACE,
            )
        };
        #[cfg(not(any(target_os = "macos", target_os = "linux")))]
        let result = {
            let linked = unsafe {
                libc::linkat(
                    source.as_raw_fd(),
                    from.as_ptr(),
                    destination.as_raw_fd(),
                    to.as_ptr(),
                    0,
                )
            };
            if linked < 0 {
                linked
            } else {
                unsafe { libc::unlinkat(source.as_raw_fd(), from.as_ptr(), 0) }
            }
        };
        if result < 0 {
            return Err(io::Error::last_os_error());
        }
        destination.sync_all()?;
        source.sync_all()?;
        Ok(())
    }
    pub fn replace(&self, from: &str, to: &str) -> io::Result<()> {
        let (source, from) = self.parent(from, false)?;
        let (destination, to) = self.parent(to, true)?;
        let result = unsafe {
            libc::renameat(
                source.as_raw_fd(),
                from.as_ptr(),
                destination.as_raw_fd(),
                to.as_ptr(),
            )
        };
        if result < 0 {
            return Err(io::Error::last_os_error());
        }
        destination.sync_all()
    }
    pub fn delete(&self, path: &str) -> io::Result<Option<u64>> {
        let file = match self.read(path) {
            Ok(file) => file,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(e),
        };
        let bytes = file.metadata()?.len();
        let (parent, leaf) = self.parent(path, false)?;
        let result = unsafe { libc::unlinkat(parent.as_raw_fd(), leaf.as_ptr(), 0) };
        if result < 0 {
            return Err(io::Error::last_os_error());
        }
        parent.sync_all()?;
        Ok(Some(bytes))
    }
    pub fn files(&self, directory: &str) -> io::Result<Vec<String>> {
        let folder = match open_directory(&self.root, directory, false) {
            Ok(folder) => folder,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(e),
        };
        let mut result = Vec::new();
        collect_files(&folder, directory, &mut result)?;
        Ok(result)
    }
}
fn collect_files(directory: &File, prefix: &str, output: &mut Vec<String>) -> io::Result<()> {
    // fdopendir owns its descriptor; dup avoids taking ownership of our handle.
    let fd = unsafe { libc::dup(directory.as_raw_fd()) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    let stream = unsafe { libc::fdopendir(fd) };
    if stream.is_null() {
        unsafe {
            libc::close(fd);
        }
        return Err(io::Error::last_os_error());
    }
    struct DirStream(*mut libc::DIR);
    impl Drop for DirStream {
        fn drop(&mut self) {
            unsafe {
                libc::closedir(self.0);
            }
        }
    }
    let stream = DirStream(stream);
    loop {
        let entry = unsafe { libc::readdir(stream.0) };
        if entry.is_null() {
            break;
        }
        let bytes = unsafe { CStr::from_ptr((*entry).d_name.as_ptr()) }.to_bytes();
        if bytes == b"." || bytes == b".." {
            continue;
        }
        let value = std::str::from_utf8(bytes)
            .map_err(|_| super::invalid("managed filename is not UTF-8"))?;
        let child = name(value)?;
        let mut metadata: libc::stat = unsafe { std::mem::zeroed() };
        if unsafe {
            libc::fstatat(
                directory.as_raw_fd(),
                child.as_ptr(),
                &mut metadata,
                libc::AT_SYMLINK_NOFOLLOW,
            )
        } < 0
        {
            return Err(io::Error::last_os_error());
        }
        let path = format!("{prefix}/{value}");
        match metadata.st_mode & libc::S_IFMT {
            libc::S_IFDIR => {
                collect_files(&open_directory(directory, value, false)?, &path, output)?
            }
            libc::S_IFREG => output.push(path),
            // Unmanaged entries never grant permission to follow or remove them.
            _ => {}
        }
    }
    Ok(())
}
