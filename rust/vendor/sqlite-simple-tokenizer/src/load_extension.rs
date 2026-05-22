use crate::simple_tokenizer::SimpleTokenizer;
use crate::utils::to_rusqlite_error;
use rusqlite::Connection;
use rusqlite::functions::Context as FunctionContext;
use rusqlite::functions::FunctionFlags;
use rusqlite::types::{ToSqlOutput, Value, ValueRef};
use rusqlite_ext::register_tokenizer;

pub fn create_scalar_functions(connection: &Connection) -> Result<(), crate::Error> {
    let deterministic = FunctionFlags::SQLITE_DETERMINISTIC | FunctionFlags::SQLITE_UTF8;

    connection.create_scalar_function(
        "simple_query",
        1,
        deterministic,
        |ctx: &FunctionContext| simple_query(ctx).map_err(to_rusqlite_error),
    )?;

    Ok(())
}

/// 将要查询的文档进行分词，单字则被转换成拼音后在做拆分，单词则对其做拆分
///
/// 返回的一个 SQLite 支持的 match 子句
fn simple_query<'a>(ctx: &FunctionContext) -> Result<ToSqlOutput<'a>, crate::Error> {
    // 第一个参数是需要查询的字符串
    let arg_input_data = 0;

    let empty_output = Ok(ToSqlOutput::Owned(Value::Null));

    let text = match ctx.get_raw(arg_input_data) {
        ValueRef::Text(t) => std::str::from_utf8(t)?,
        value => {
            let ty = value.data_type().to_string();
            return Err(crate::Error::SimpleQueryInputTypeIncorrect(ty));
        }
    };

    if let Some(match_sql) = SimpleTokenizer::tokenize_query(text) {
        return Ok(ToSqlOutput::Owned(Value::Text(match_sql)));
    };

    empty_output
}

pub fn load_fts5_extension(connection: &Connection) -> Result<(), crate::Error> {
    // 注册 simple_tokenizer
    register_tokenizer::<SimpleTokenizer>(connection, ())?;
    Ok(())
}
