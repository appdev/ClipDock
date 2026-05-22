use crate::pinyin::{get_pinyin, has_pinyin, split_pinyin};
use rusqlite::Error;
use rusqlite_ext::{TokenizeReason, Tokenizer};
use sqlite_chinese_stopword::STOPWORD;
use sqlite_english_stemmer::{EN_STEMMER, make_lowercase};
use std::ffi::CStr;
use std::ops::Range;
use unicode_segmentation::UnicodeSegmentation;

/// 适用于拼音和中文的分词器
pub struct SimpleTokenizer {
    /// 是否支持拼音，默认支持拼音
    enable_pinyin: bool,
    /// 是否启用停词表, 默认启用
    enable_stopword: bool,
}

impl Default for SimpleTokenizer {
    fn default() -> Self {
        Self {
            enable_pinyin: true,
            enable_stopword: true,
        }
    }
}

impl SimpleTokenizer {
    /// 关闭拼音分词
    pub fn disable_pinyin(&mut self) {
        self.enable_pinyin = false;
    }
    /// 不启用停词表
    pub fn disable_stopword(&mut self) {
        self.enable_stopword = false;
    }
    /// 将查询文档转换成 SQLite 的 match 语句
    pub fn tokenize_query(text: &str) -> Option<String> {
        let mut match_sql = "".to_owned();
        for (_, word) in text.unicode_word_indices() {
            // 判断是否是单字
            if need_pinyin(word) {
                if let Some(ch) = word.chars().next() {
                    if let Some(pinyin_vec) = get_pinyin(&ch) {
                        for pinyin in pinyin_vec {
                            let sql = Self::split_pinyin_to_sql(&pinyin);
                            Self::append_match_sql(sql, &mut match_sql);
                        }
                    }
                }
            } else {
                let sql = Self::split_pinyin_to_sql(word);
                Self::append_match_sql(sql, &mut match_sql);
            }
        }
        Some(match_sql)
    }

    fn append_match_sql(sql: String, buf: &mut String) {
        if buf.is_empty() {
            buf.push('(');
        } else {
            buf.push_str(" AND (");
        }
        buf.push_str(&sql);
        buf.push(')');
    }

    fn split_pinyin_to_sql(word: &str) -> String {
        let pinyin_set = split_pinyin(word);
        pinyin_set
            .into_iter()
            .fold(String::new(), |mut acc, pinyin| {
                if acc.is_empty() {
                    acc.push_str(&pinyin);
                    acc.push('*');
                } else {
                    acc.push_str(" OR ");
                    acc.push_str(&pinyin);
                    acc.push('*');
                };
                acc
            })
    }
}

impl Tokenizer for SimpleTokenizer {
    type Global = ();

    fn name() -> &'static CStr {
        c"simple"
    }

    fn new(_global: &Self::Global, args: Vec<String>) -> Result<Self, Error> {
        let mut tokenizer = Self::default();
        for arg in args {
            match arg.as_str() {
                "disable_pinyin" => {
                    tokenizer.disable_pinyin();
                }
                "disable_stopword" => {
                    tokenizer.disable_stopword();
                }
                _ => {}
            }
        }
        Ok(tokenizer)
    }

    fn tokenize<TKF>(
        &mut self,
        _reason: TokenizeReason,
        text: &[u8],
        mut push_token: TKF,
    ) -> Result<(), Error>
    where
        TKF: FnMut(&[u8], Range<usize>, bool) -> Result<(), Error>,
    {
        let text = String::from_utf8_lossy(text);
        // 使用 unicode_word_indices 进行分词，所有中文字符应该是单独一个字符成 word
        let mut word_buf = String::new();
        for (index, word) in text.unicode_word_indices() {
            let range = index..index + word.len();
            // 开启 pinyin 并且这个是中文字符
            if self.enable_pinyin && need_pinyin(word) {
                if self.enable_stopword && STOPWORD.contains(word) {
                    // 不处理停词
                    continue;
                }
                if let Some(ch) = word.chars().next() {
                    if let Some(pinyin_vec) = get_pinyin(&ch) {
                        for pinyin in pinyin_vec {
                            (push_token)(pinyin.as_bytes(), range.clone(), false)?;
                        }
                    }
                }
            } else {
                // 不需要使用 pinyin 模块进行处理
                // 对单词做归一化处理，并且将单词转换成小写
                let need_stem = make_lowercase(word, &mut word_buf);
                if self.enable_stopword && STOPWORD.contains(word_buf.as_str()) {
                    // 不处理停词
                    continue;
                }
                if need_stem {
                    let stemmed = EN_STEMMER.stem(word_buf.as_str()).into_owned();
                    (push_token)(stemmed.as_bytes(), range, false)?;
                } else {
                    (push_token)(word_buf.as_bytes(), range, false)?;
                }
            }
        }
        Ok(())
    }
}

/// 判断这个单词是否需要使用 pinyin 模块进行处理
fn need_pinyin(word: &str) -> bool {
    if word.is_empty() || word.chars().count() > 1 {
        // 空串，或者字符个数大于 1 的单词，不需要 pinyin 处理
        return false;
    }
    if let Some(ch) = word.chars().next() {
        return has_pinyin(&ch);
    }
    false
}

#[cfg(test)]
mod tests {
    use unicode_segmentation::UnicodeSegmentation;

    #[test]
    fn test_tokenize_by_unicode_word_indices() {
        let text = "The quick (\"brown\") fox can't jump 32.3 feet, right? 我将点燃星海！天上的stars全部都是 eye，不要凝视";
        let uwi1 = text.unicode_word_indices().collect::<Vec<(usize, &str)>>();
        let b: &[_] = &[
            (0, "The"),
            (4, "quick"),
            (12, "brown"),
            (20, "fox"),
            (24, "can't"),
            (30, "jump"),
            (35, "32.3"),
            (40, "feet"),
            (46, "right"),
            (53, "我"),
            (56, "将"),
            (59, "点"),
            (62, "燃"),
            (65, "星"),
            (68, "海"),
            (74, "天"),
            (77, "上"),
            (80, "的"),
            (83, "stars"),
            (88, "全"),
            (91, "部"),
            (94, "都"),
            (97, "是"),
            (101, "eye"),
            (107, "不"),
            (110, "要"),
            (113, "凝"),
            (116, "视"),
        ];
        assert_eq!(&uwi1[..], b);
    }
}
