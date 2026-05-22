#[cfg(feature = "build_extension")]
mod create_extension;
mod load_extension;
mod pinyin;
pub mod simple_tokenizer;
mod utils;

use load_extension::create_scalar_functions;
use load_extension::load_fts5_extension;
use log::LevelFilter;
use rusqlite::Connection;
use rusqlite_ext::error::Error;
use utils::init_logging;

pub fn load(connection: &Connection) -> Result<(), Error> {
    load_with_loglevel(connection, LevelFilter::Info)
}

pub fn load_with_loglevel(connection: &Connection, log_level: LevelFilter) -> Result<(), Error> {
    // 设置 log
    init_logging(log_level);
    // 加载拓展函数
    create_scalar_functions(connection)?;
    // 加载 fts5 拓展
    load_fts5_extension(connection)
}

#[cfg(test)]
mod tests {
    use crate::load;
    use rusqlite::Connection;

    #[test]
    fn test_simple_query() {
        let conn = Connection::open_in_memory().unwrap();
        load(&conn).unwrap();
        let mut stmt = conn.prepare("SELECT simple_query('国')").unwrap();
        let result = stmt
            .query_map([], |row| Ok(row.get::<_, String>(0).unwrap()))
            .unwrap();
        let mut vec = Vec::new();
        for row in result {
            let row = row.unwrap();
            vec.push(row)
        }
        assert_eq!(["(g+u+o* OR gu+o* OR guo*)"], vec.as_slice());
    }

    #[test]
    fn test_simple() {
        let conn = Connection::open_in_memory().unwrap();
        load(&conn).unwrap();
        // 创建一个测试表
        conn.execute(
            "CREATE VIRTUAL TABLE t1 USING fts5(text, tokenize = 'simple');",
            [],
        )
        .unwrap();
        // 插入数据
        conn.execute(
            r#"INSERT INTO t1(text) VALUES ('中华人民共和国国歌'),('静夜思'),('国家'),('举头望明月'),('like'),('liking'),('liked'),('I''m making a sqlite tokenizer'),('I''m learning English');"#,
            [],
        )
            .unwrap();
        let mut stmt = conn
            .prepare("SELECT * FROM t1 WHERE text MATCH simple_query('国');")
            .unwrap();
        let result = stmt
            .query_map([], |row| Ok(row.get::<_, String>(0).unwrap()))
            .unwrap();
        let mut vec = Vec::new();
        for row in result {
            let row = row.unwrap();
            vec.push(row)
        }
        assert_eq!(["中华人民共和国国歌", "国家"], vec.as_slice());
    }
}
