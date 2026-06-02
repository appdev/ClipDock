use std::{
    env,
    net::SocketAddr,
    path::{Path, PathBuf},
};

use anyhow::{anyhow, Context, Result};

#[derive(Clone, Debug)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub database_path: PathBuf,
    pub asset_dir: PathBuf,
    pub max_asset_bytes: usize,
}

impl Config {
    pub const DEFAULT_MAX_ASSET_BYTES: usize = 2 * 1024 * 1024;

    pub fn from_env_args() -> Result<Self> {
        let mut bind_addr = env::var("CLIPDOCK_BIND_ADDR")
            .unwrap_or_else(|_| "127.0.0.1:8787".to_string())
            .parse()
            .context("invalid CLIPDOCK_BIND_ADDR")?;
        let mut database_path = env::var("CLIPDOCK_DATABASE")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("data/clipdock-sync.sqlite"));
        let mut asset_dir = env::var("CLIPDOCK_ASSET_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("data/assets"));
        let mut max_asset_bytes = env::var("CLIPDOCK_MAX_ASSET_BYTES")
            .ok()
            .map(|value| value.parse())
            .transpose()
            .context("invalid CLIPDOCK_MAX_ASSET_BYTES")?
            .unwrap_or(Self::DEFAULT_MAX_ASSET_BYTES);

        let args = env::args().skip(1).collect::<Vec<_>>();
        let mut index = 0;
        while index < args.len() {
            let key = &args[index];
            let value = args
                .get(index + 1)
                .ok_or_else(|| anyhow!("missing value for {key}"))?;
            match key.as_str() {
                "--bind" => bind_addr = value.parse().context("invalid --bind")?,
                "--database" => database_path = PathBuf::from(value),
                "--assets" => asset_dir = PathBuf::from(value),
                "--max-asset-bytes" => {
                    max_asset_bytes = value.parse().context("invalid --max-asset-bytes")?
                }
                other => return Err(anyhow!("unknown argument {other}")),
            }
            index += 2;
        }

        Ok(Self {
            bind_addr,
            database_path,
            asset_dir,
            max_asset_bytes,
        })
    }

    pub fn for_tests(root: &Path) -> Self {
        Self {
            bind_addr: "127.0.0.1:0".parse().expect("valid test bind address"),
            database_path: root.join("clipdock-sync.sqlite"),
            asset_dir: root.join("assets"),
            max_asset_bytes: Self::DEFAULT_MAX_ASSET_BYTES,
        }
    }
}
