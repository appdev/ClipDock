use std::collections::HashMap;
use unicode_segmentation::UnicodeSegmentation;

const MAX_ENTRIES: usize = 1_024;

#[derive(Clone, PartialEq, Eq, Hash)]
struct Key {
    content_identity: [u8; 32],
    byte_length: usize,
    // Rich-text identity hashes the RTF asset, so its alternate plain text can
    // change without changing content_hash (even at the same byte length).
    text_fingerprint: Option<[u8; 32]>,
}

struct Entry {
    scalar_count: i64,
    trimmed_grapheme_count: Option<i64>,
    last_access: u64,
}

/// Per-core bounded counts only. No body, preview or asset is retained.
#[derive(Default)]
pub(super) struct TextMetricsCache {
    entries: HashMap<Key, Entry>,
    clock: u64,
    #[cfg(test)]
    scalar_computations: usize,
    #[cfg(test)]
    grapheme_computations: usize,
}

impl TextMetricsCache {
    pub(super) fn get(
        &mut self,
        content_hash: &str,
        text: &str,
        include_graphemes: bool,
        verify_alternate_body: bool,
    ) -> (Option<i64>, i64) {
        let key = Key {
            // Fixed-size key also bounds memory if a legacy/imported hash is
            // unusually long. Neither identity string nor body is retained.
            content_identity: *blake3::hash(content_hash.as_bytes()).as_bytes(),
            byte_length: text.len(),
            // Plain-text identity already hashes this exact normalized body.
            // Only RTF-based identities need another body verification pass.
            text_fingerprint: verify_alternate_body
                .then(|| *blake3::hash(text.as_bytes()).as_bytes()),
        };
        self.clock = self.clock.saturating_add(1);
        if !self.entries.contains_key(&key) {
            if self.entries.len() >= MAX_ENTRIES {
                if let Some(oldest) = self
                    .entries
                    .iter()
                    .min_by_key(|(_, entry)| entry.last_access)
                    .map(|(key, _)| key.clone())
                {
                    self.entries.remove(&oldest);
                }
            }
            self.entries.insert(
                key.clone(),
                Entry {
                    scalar_count: text.chars().count() as i64,
                    trimmed_grapheme_count: None,
                    last_access: self.clock,
                },
            );
            #[cfg(test)]
            {
                self.scalar_computations += 1;
            }
        }
        let entry = self.entries.get_mut(&key).expect("metrics inserted");
        entry.last_access = self.clock;
        if include_graphemes && entry.trimmed_grapheme_count.is_none() {
            entry.trimmed_grapheme_count = Some(trimmed_grapheme_count(text));
            #[cfg(test)]
            {
                self.grapheme_computations += 1;
            }
        }
        (
            if include_graphemes {
                entry.trimmed_grapheme_count
            } else {
                None
            },
            entry.scalar_count,
        )
    }
}

fn trimmed_grapheme_count(text: &str) -> i64 {
    // Foundation whitespacesAndNewlines includes U+200B as well as White_Space.
    let trimmed = text.trim_matches(|value: char| value.is_whitespace() || value == '\u{200b}');
    // ASCII has one grapheme per byte except CRLF. Keep the general Unicode
    // algorithm for combining marks, emoji sequences and other scripts.
    if trimmed.is_ascii() {
        (trimmed.len()
            - trimmed
                .as_bytes()
                .windows(2)
                .filter(|pair| *pair == b"\r\n")
                .count()) as i64
    } else {
        trimmed.graphemes(true).count() as i64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cold_hot_and_optional_metric_upgrade_are_identical() {
        let mut cache = TextMetricsCache::default();
        let text = "\u{200b}e\u{301}\r\n👩‍👩‍👧‍👦 🇺🇸\u{0085}";
        let scalar = text.chars().count() as i64;
        assert_eq!(cache.get("same", text, false, false), (None, scalar));
        assert_eq!(cache.scalar_computations, 1);
        assert_eq!(cache.grapheme_computations, 0);
        let cold = cache.get("same", text, true, false);
        assert_eq!(cold, (Some(trimmed_grapheme_count(text)), scalar));
        assert_eq!(cache.get("same", text, true, false), cold);
        assert_eq!(cache.get("same", text, false, false), (None, scalar));
        assert_eq!(cache.scalar_computations, 1);
        assert_eq!(cache.grapheme_computations, 1);
        assert_eq!(cache.entries.len(), 1);
    }

    #[test]
    fn identity_and_alternate_plain_text_changes_invalidate_metrics() {
        let mut cache = TextMetricsCache::default();
        assert_eq!(cache.get("hash-a", "e\u{301}", true, true), (Some(1), 2));
        assert_eq!(cache.get("hash-a", "e\u{301}", true, true), (Some(1), 2));
        assert_eq!(cache.scalar_computations, 1);
        // Same body with a different content identity must get its own entry.
        cache.get("hash-b", "e\u{301}", true, true);
        assert_eq!(cache.scalar_computations, 2);
        // A rich-text alternate body can have the same hash and byte length.
        assert_eq!("e\u{301}".len(), "abc".len());
        assert_eq!(cache.get("hash-a", "abc", true, true), (Some(3), 3));
        assert_eq!(cache.scalar_computations, 3);
        assert_eq!(cache.get("hash-a", "longer", true, true), (Some(6), 6));
        assert_eq!(cache.scalar_computations, 4);
    }

    #[test]
    fn cache_is_bounded_and_evicts_the_least_recently_used_entry() {
        let mut cache = TextMetricsCache::default();
        for index in 0..MAX_ENTRIES {
            cache.get(&index.to_string(), "body", true, false);
        }
        cache.get("0", "body", true, false); // Protect this older but recently read key.
        cache.get("new", "body", true, false);
        assert_eq!(cache.entries.len(), MAX_ENTRIES);
        let computations = cache.scalar_computations;
        cache.get("0", "body", true, false);
        assert_eq!(cache.scalar_computations, computations);
        cache.get("1", "body", true, false);
        assert_eq!(cache.scalar_computations, computations + 1);
        for index in MAX_ENTRIES..MAX_ENTRIES * 3 {
            cache.get(&index.to_string(), "body", false, false);
            assert_eq!(cache.entries.len(), MAX_ENTRIES);
        }
    }
}
