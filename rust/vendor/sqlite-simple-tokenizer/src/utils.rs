use std::env;

pub fn to_rusqlite_error(error: crate::Error) -> rusqlite::Error {
    rusqlite::Error::UserFunctionError(format!("{error:?}").into())
}

pub fn init_logging(default_level: log::LevelFilter) {
    const LOG_LEVEL_ENV: &str = "SQLITE_SIMPLE_TOKENIZER_LOG";

    if env::var(LOG_LEVEL_ENV).is_err() {
        unsafe { env::set_var(LOG_LEVEL_ENV, default_level.to_string()) }
    }

    let logger_level = env_logger::Env::new().filter(LOG_LEVEL_ENV);

    env_logger::try_init_from_env(logger_level).ok();
}
