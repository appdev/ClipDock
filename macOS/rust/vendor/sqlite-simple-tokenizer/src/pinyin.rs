use phf::phf_set;
use std::char;
use std::collections::BTreeSet;

include!(concat!(env!("OUT_DIR"), "/pinyin_data.rs"));

/// 通过给定的字符，判断是否有拼音
pub fn has_pinyin(ch: &char) -> bool {
    PINYIN_DIRT.contains_key(ch)
}

/// 通过字符获取拼音
pub fn get_pinyin(ch: &char) -> Option<Vec<String>> {
    let pinyin = PINYIN_DIRT.get(ch)?;
    let result = pinyin
        .split(",")
        .map(str::to_owned)
        .collect::<Vec<String>>();
    Some(result)
}

/// 获取这个拼音字符串中全部拼音组合，包含原始输入、全部字母组合、全部合法拼音组合
///
/// 如果提供空串、一个字母的拼音串、超过 20 个字符的拼音串均不处理，原样返回
///
/// 例如
/// - `ba` 得到 `{"ba", "b+a"}`
/// - `zhuang` 得到 `{"zhuang", "z+h+u+a+n+g", "zhu+ang", "zhu+an+g", "zhuan+g"}`
/// - `zhangliangying` 得到  `{"zhangliangying", "zhang+li+ang+yin+g", "zhang+li+ang+ying", "zhang+liang+yin+g", "zhang+liang+ying", "z+h+a+n+g+l+i+a+n+g+y+i+n+g"}`
/// - `zhangliangy` 得到  `{"zhangliangy", "zhang+li+ang+y", "zhang+liang+y", "z+h+a+n+g+l+i+a+n+g+y+i+n+g"}`
pub fn split_pinyin(input: &str) -> BTreeSet<String> {
    let len = input.chars().count();
    const MAX_LEN: usize = 20;
    if len <= 1 || len > MAX_LEN {
        return BTreeSet::from([input.to_owned()]);
    }
    let spaced = input
        .chars()
        .fold(String::new(), |mut acc, ch| {
            acc.push('+');
            acc.push(ch);
            acc
        })
        .chars()
        .skip(1)
        .collect::<String>();
    if len > 2 {
        let pinyin = split_pinyin_with_index(input, 0, len);
        // 去重
        let mut pinyin = pinyin.into_iter().collect::<BTreeSet<_>>();
        pinyin.insert(spaced);
        pinyin.insert(input.to_owned());
        pinyin
    } else {
        BTreeSet::from([input.to_owned(), spaced])
    }
}

/// 用于获取这个拼音字符串中全部拼音组合
///
/// 在列举拼音组合时，前面都需要考虑符合完整的拼音，最后一个字母可以只考虑是否是某个拼音的前缀。
fn split_pinyin_with_index(input: &str, begin: usize, end: usize) -> Vec<String> {
    if begin >= end {
        return Vec::new();
    }
    if begin == end - 1 {
        // 只有一个字符的时候，将这个字符返回
        return vec![input[begin..end].to_owned()];
    }
    let mut result = Vec::<String>::new();
    let full_str = &input[begin..end];
    if PINYIN_PREFIX.contains(full_str) || PINYIN_VALID.contains(full_str) {
        // 整个字符串是合法的拼音，那么保存到结果中
        result.push(full_str.to_owned());
    }
    let mut start = begin + 1;
    while start < end {
        let first = &input[begin..start];
        if !PINYIN_VALID.contains(first) {
            // 当前子串不是合法拼音，调整索引，往当前子串添加一个新字符
            start += 1;
            continue;
        }
        // 找到第一个拼音，后将剩余的子串继续分割
        let tmp = split_pinyin_with_index(input, start, end);
        // 只有剩余的子串中有合法拼音，那么这个拼音有效
        // 如果剩余的子串没有合法拼音，那么这个拼音和后续的字符才是一个比较完整的拼音，将跳过这个拼音
        for s in tmp {
            result.push(format!("{first}+{s}"));
        }
        start += 1
    }
    result
}

/// 不是合法拼音，但可以是拼音前缀，只能出现在将拼音分割成拼音组合的结尾
static PINYIN_PREFIX: phf::Set<&'static str> = phf_set! {
    "be","bia",
    "ch","cho","chon","chua","co","con","cua",
    "din","don","do","dua",
    "fe",
    "go","gon",
    "ho","hon",
    "len","lon","lua",
    "mia",
    "nia","no","non","nua",
    "pe","pia",
    "qio","qion","qua",
    "ra","ro","ron","rua",
    "sh","sho","so","son","sua",
    "ten","tia","tin","to","ton","tua",
    "we",
    "xio","xion","xua",
    "yon","yua",
    "zh","zho","zhon","zo","zon","zua",
};

/// 合法拼音
static PINYIN_VALID: phf::Set<&'static str> = phf_set! {
    "a", "ai", "an", "ang", "ao",
    "ba", "bai", "ban", "bang", "bao", "bei", "ben", "beng", "bi", "bian", "biao", "bie", "bin", "bing", "bo", "bu",
    "ca", "cai", "can", "cang", "cao", "ce", "cen", "ceng", "cha", "chai", "chan", "chang", "chao", "che", "chen", "cheng", "chi", "chong", "chou", "chu", "chuai", "chuan", "chuang", "chui", "chun", "chuo", "ci", "cong", "cou", "cu", "cuan", "cui", "cun", "cuo",
    "da", "dai", "dan", "dang", "dao", "de", "dei", "den", "deng", "di", "dia", "dian", "diao", "die", "ding", "diu", "dong", "dou", "du", "duan", "dui", "dun", "duo",
    "e", "ei", "en", "eng", "er",
    "fa", "fan", "fang", "fei", "fen", "feng", "fo", "fou", "fu",
    "ga", "gai", "gan", "gang", "gao", "ge", "gei", "gen", "geng", "gong", "gou", "gu", "gua", "guai", "guan", "guang", "gui", "gun", "guo",
    "ha", "hai", "han", "hang", "hao", "he", "hei", "hen", "heng", "hong", "hou", "hu", "hua", "huai", "huan", "huang", "hui", "hun", "huo",
    // "i"=>[],
    "ji", "jia", "jian", "jiang", "qiao", "jiao", "jie", "jin", "jing", "jiong", "jiu", "ju", "juan", "jue", "jun","jv",
    "ka", "kai", "kan", "kang", "kao", "ke", "kei", "ken", "keng", "kong", "kou", "ku", "kua", "kuai", "kuan", "kuang", "kui", "kun", "kuo",
    "la", "lai", "lan", "lang", "lao", "le", "lei", "leng", "li", "lia", "lian", "liang", "liao", "lie", "lin", "ling", "liu", "long", "lo", "lou", "lu", "luan", "lue", "lun", "luo","lv",
    "ma", "mai", "man", "mang", "mao", "me", "mei", "men", "meng", "mi", "mian", "miao", "mie", "min", "ming", "miu", "mo", "mou", "mu",
    "na", "nai", "nan", "nang", "nao", "ne", "nei", "nen", "neng", "ni", "nian", "niang", "niao", "nie", "nin", "ning", "niu", "nong", "nou", "nu", "nuan", "nue", "nun", "nuo", "nv",
    "o", "ou",
    "pa", "pai", "pan", "pang", "pao", "pei", "pen",
    "peng", "pi", "pian", "piao", "pie", "pin", "ping", "po", "pou", "pu",
    "qi", "qia", "qian", "qiang", "qie", "qin", "qing", "qiong", "qiu", "qu", "quan", "que", "qun","qv",
    "ran", "rang", "rao", "re", "ren", "reng", "ri", "rong", "rou", "ru", "ruan", "rui", "run", "ruo",
    "sa", "sai", "san", "sang", "sao", "se", "sen", "seng", "sha", "shai", "shan", "shang", "shao", "she", "shei", "shen", "sheng", "shi", "shou", "shu", "shua", "shuai", "shuan", "shuang", "shui", "shun", "shuo", "si", "song", "sou", "su", "suan", "sui", "sun", "suo",
    "ta", "tai", "tan", "tang", "tao", "te", "tei", "teng", "ti", "tian", "tiao", "tie", "ting", "tong", "tou", "tu", "tuan", "tui", "tun", "tuo",
    // "u"=>[],
    // "v"=>[],
    "wa", "wai", "wan", "wang", "wei", "wen", "weng", "wo", "wu",
    "xi", "xia", "xian", "xiang", "xiao", "xie", "xin", "xing", "xiong", "xiu", "xu", "xuan", "xue", "xun","xv",
    "ya", "yan", "yang","yao", "ye", "yi", "yin", "ying", "yo", "yong", "you", "yu", "yuan", "yue", "yun",
    "za", "zai", "zan", "zang", "zao", "ze", "zei", "zen", "zeng", "zha", "zhai", "zhan", "zhang", "zhao", "zhe", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu", "zhua", "zhuai", "zhuan", "zhuang", "zhui", "zhun", "zhuo", "zi", "zong", "zou", "zu", "zuan", "zui", "zun", "zuo",
};

#[cfg(test)]
mod tests {
    use crate::pinyin::{PINYIN_DIRT, get_pinyin, split_pinyin};
    use std::collections::BTreeSet;

    #[test]
    fn test_get_pinyin_by_dirt() {
        let ch = '中';
        let pinyin = *PINYIN_DIRT.get(&ch).unwrap();
        assert_eq!("zhong", pinyin);
        let ch = '说';
        let pinyin = *PINYIN_DIRT.get(&ch).unwrap();
        assert_eq!("shui,shuo,yue", pinyin);
    }

    #[test]
    fn test_get_pinyin() {
        let ch = '中';
        let pinyin = get_pinyin(&ch).unwrap();
        assert_eq!(vec!["zhong".to_owned()], pinyin);
        let ch = '说';
        let pinyin = get_pinyin(&ch).unwrap();
        assert_eq!(
            vec!["shui".to_owned(), "shuo".to_owned(), "yue".to_owned()],
            pinyin
        );
    }

    #[test]
    fn test_split_pinyin() {
        let input = "";
        assert_eq!(BTreeSet::from(["".to_owned()]), split_pinyin(input));
        let input = "a";
        assert_eq!(BTreeSet::from(["a".to_owned()]), split_pinyin(input));
        let input = "ba";
        assert_eq!(
            BTreeSet::from(["ba".to_owned(), "b+a".to_owned()]),
            split_pinyin(input)
        );
        let input = "zhuang";
        assert_eq!(
            BTreeSet::from([
                "z+h+u+a+n+g".to_owned(),
                "zhuang".to_owned(),
                "zhuan+g".to_owned(),
                "zhu+ang".to_owned(),
                "zhu+an+g".to_owned(),
            ]),
            split_pinyin(input)
        );
        let input = "zhangliangy";
        assert_eq!(
            BTreeSet::from([
                "z+h+a+n+g+l+i+a+n+g+y".to_owned(),
                "zhangliangy".to_owned(),
                "zhang+li+ang+y".to_owned(),
                "zhang+liang+y".to_owned(),
            ]),
            split_pinyin(input)
        );
        let input = "zhangliangying";
        assert_eq!(
            BTreeSet::from([
                "zhangliangying".to_owned(),
                "zhang+li+ang+ying".to_owned(),
                "zhang+li+ang+yin+g".to_owned(),
                "zhang+liang+ying".to_owned(),
                "zhang+liang+yin+g".to_owned(),
                "z+h+a+n+g+l+i+a+n+g+y+i+n+g".to_owned()
            ]),
            split_pinyin(input)
        );
        let input = "zhangliangyingzhangliangying";
        assert_eq!(
            BTreeSet::from(["zhangliangyingzhangliangying".to_owned()]),
            split_pinyin(input)
        );
    }
}
