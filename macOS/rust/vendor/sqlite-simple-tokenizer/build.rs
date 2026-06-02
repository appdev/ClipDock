use std::collections::{BTreeSet, HashMap};
use std::env;
use std::fs::File;
use std::io::BufWriter;
use std::io::Write;
use std::path::Path;
use std::sync::LazyLock;

static DEFAULT_PINYIN_DATA: &str = include_str!("data/pinyin.txt");

/// 带声调的韵母和和不带声调的韵母的映射
static TONE_TO_PLAIN: LazyLock<HashMap<char, char>> = LazyLock::new(|| {
    HashMap::from([
        ('ā', 'a'),
        ('á', 'a'),
        ('ǎ', 'a'),
        ('à', 'a'),
        ('ē', 'e'),
        ('é', 'e'),
        ('ě', 'e'),
        ('è', 'e'),
        ('ế', 'e'),
        ('ề', 'e'),
        ('ê', 'e'),
        ('ō', 'o'),
        ('ó', 'o'),
        ('ǒ', 'o'),
        ('ò', 'o'),
        ('ī', 'i'),
        ('í', 'i'),
        ('ǐ', 'i'),
        ('ì', 'i'),
        ('ū', 'u'),
        ('ú', 'u'),
        ('ǔ', 'u'),
        ('ù', 'u'),
        ('ǘ', 'u'),
        ('ǚ', 'u'),
        ('ǜ', 'u'),
        ('ü', 'u'),
        ('ń', 'n'),
        ('ň', 'n'),
        ('ǹ', 'n'),
        ('ḿ', 'm'),
    ])
});

/// 将拼音中带有声调的韵母转换为不带声调的韵母
fn to_plain(input: &str) -> String {
    let value = input
        .chars()
        .map(|ch| {
            if let Some(char) = TONE_TO_PLAIN.get(&ch) {
                char.to_owned()
            } else {
                ch
            }
        })
        .collect::<String>();
    let values = value.split(",").map(str::trim).collect::<BTreeSet<&str>>();
    let mut pinyin = "\"".to_owned();
    let len = values.len() - 1;
    for (index, value) in values.iter().enumerate() {
        pinyin.push_str(value);
        if index != len {
            pinyin.push(',');
        }
    }
    pinyin.push('"');

    pinyin
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=data/pinyin.txt");
    println!("cargo:rerun-if-changed=data/stopword.txt");

    // 借助汉字码点和拼音的映射表，构建一个 char 与拼音映射的全局字典
    let path = Path::new(&env::var("OUT_DIR").unwrap()).join("pinyin_data.rs");
    let mut file = BufWriter::new(File::create(&path).unwrap());
    let mut dirt = phf_codegen::Map::new();
    for line in DEFAULT_PINYIN_DATA.split("\n") {
        if line.is_empty() || line.starts_with("#") {
            continue;
        }
        // 第一个是码点，第二个是拼音集合
        let mut codepoint_and_pinyin = line.split(": ");
        let codepoint = if let Some(codepoint) = codepoint_and_pinyin.next() {
            char::from_u32(u32::from_str_radix(&codepoint[2..], 16).unwrap()).unwrap()
        } else {
            char::default()
        };
        let pinyin = if let Some(pinyin) = codepoint_and_pinyin.next() {
            to_plain(pinyin)
        } else {
            String::default()
        };
        dirt.entry(codepoint, pinyin);
    }

    write!(
        &mut file,
        "static PINYIN_DIRT: phf::Map<char, &'static str> = {}",
        dirt.build()
    )
    .unwrap();
    writeln!(&mut file, ";").unwrap();
}
