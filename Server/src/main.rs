use anyhow::Result;
use clipdock_sync_server::{
    api::{self, AppState},
    assets::AssetStore,
    config::Config,
    db, lifecycle, migrations,
    realtime::EventHub,
};
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::from_env_args()?;
    let pool = db::connect(&config).await?;
    migrations::migrate(&pool).await?;
    let assets = AssetStore::new(config.asset_dir.clone(), config.max_asset_bytes).await?;
    tokio::spawn(lifecycle::run_empty_space_cleanup_loop(
        pool.clone(),
        assets.clone(),
    ));
    let bind_addr = config.bind_addr;
    let app = api::router(AppState {
        pool,
        config,
        assets,
        realtime: EventHub::new(),
    });

    let listener = TcpListener::bind(bind_addr).await?;
    println!(
        "ClipDock sync server listening on http://{}",
        listener.local_addr()?
    );
    axum::serve(listener, app).await?;
    Ok(())
}
