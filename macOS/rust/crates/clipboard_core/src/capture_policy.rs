//! Pure compatibility policy. Native adapters supply source facts before payload reads.
use crate::{CoreError, CoreErrorCode, Result, SourceConfidence};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapturePolicyProfile {
    MacOsV1,
    WindowsV1,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CapturePolicyInput {
    pub profile: CapturePolicyProfile,
    /// Mac: Foundation trim/lowercase/NFC and native path decomposition.
    /// Windows: the compatibility helpers below. Empty keys are not candidates.
    pub source_candidate_keys: Vec<String>,
    /// Retain original rule order, including empty entries, for index mapping.
    pub application_rule_keys: Vec<String>,
    pub skip_unknown_source: bool,
    pub source_confidence: SourceConfidence,
    pub has_owner: bool,
    pub title_match_index: Option<usize>,
    pub title_rule_count: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapturePolicyReason {
    UnknownSource,
    SourceApplication,
    WindowTitle,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapturePolicyDecision {
    pub skip: bool,
    pub reason: Option<CapturePolicyReason>,
    pub matched_rule_index: Option<usize>,
}

pub fn evaluate_capture_policy(input: &CapturePolicyInput) -> Result<CapturePolicyDecision> {
    if input
        .title_match_index
        .is_some_and(|index| index >= input.title_rule_count)
    {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "title match index is outside the native rule list",
        ));
    }
    let candidates_empty = input.source_candidate_keys.iter().all(String::is_empty);
    let unknown = match input.profile {
        CapturePolicyProfile::MacOsV1 => candidates_empty,
        CapturePolicyProfile::WindowsV1 => {
            candidates_empty
                || !input.has_owner
                || input.source_confidence != SourceConfidence::High
        }
    };
    let (reason, matched_rule_index) = if input.skip_unknown_source && unknown {
        (Some(CapturePolicyReason::UnknownSource), None)
    } else if let Some(index) = input
        .application_rule_keys
        .iter()
        .position(|rule| !rule.is_empty() && input.source_candidate_keys.contains(rule))
    {
        (Some(CapturePolicyReason::SourceApplication), Some(index))
    } else if let Some(index) = input.title_match_index {
        (Some(CapturePolicyReason::WindowTitle), Some(index))
    } else {
        (None, None)
    };
    Ok(CapturePolicyDecision {
        skip: reason.is_some(),
        reason,
        matched_rule_index,
    })
}

pub fn normalize_windows_capture_key(value: &str) -> String {
    value.trim().replace('/', "\\").to_lowercase()
}

pub fn windows_capture_source_keys(name: Option<&str>, path: Option<&str>) -> Vec<String> {
    let mut candidates = Vec::new();
    for value in [name, path].into_iter().flatten() {
        let value = normalize_windows_capture_key(value);
        if value.is_empty() {
            continue;
        }
        let name = value.rsplit('\\').next().unwrap_or(&value).to_owned();
        candidates.push(name.strip_suffix(".exe").unwrap_or(&name).to_owned());
        candidates.push(name);
        candidates.push(value);
    }
    candidates
}

#[cfg(test)]
mod tests {
    use super::*;
    fn input() -> CapturePolicyInput {
        CapturePolicyInput {
            profile: CapturePolicyProfile::MacOsV1,
            source_candidate_keys: vec!["editor".into()],
            application_rule_keys: vec!["".into(), "editor".into(), "editor".into()],
            skip_unknown_source: true,
            source_confidence: SourceConfidence::Low,
            has_owner: false,
            title_match_index: Some(0),
            title_rule_count: 1,
        }
    }
    #[test]
    fn compatibility_profiles_keep_distinct_unknown_source_facts() {
        let mut facts = input();
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().reason,
            Some(CapturePolicyReason::SourceApplication)
        );
        facts.profile = CapturePolicyProfile::WindowsV1;
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().reason,
            Some(CapturePolicyReason::UnknownSource)
        );
        facts.has_owner = true;
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().reason,
            Some(CapturePolicyReason::UnknownSource)
        );
        facts.source_confidence = SourceConfidence::High;
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().matched_rule_index,
            Some(1)
        );
        facts.source_candidate_keys = vec![String::new()];
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().reason,
            Some(CapturePolicyReason::UnknownSource)
        );
    }
    #[test]
    fn priority_and_native_title_indices_are_checked_without_reinterpreting_keys() {
        let mut facts = input();
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().matched_rule_index,
            Some(1)
        );
        facts.application_rule_keys = vec!["edit".into()];
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().reason,
            Some(CapturePolicyReason::WindowTitle)
        );
        facts.title_match_index = None;
        assert!(!evaluate_capture_policy(&facts).unwrap().skip);
        facts.title_match_index = Some(1);
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap_err().code,
            CoreErrorCode::InvalidInput
        );
        facts.title_match_index = None;
        facts.application_rule_keys = vec!["é".into()];
        facts.source_candidate_keys = vec!["é".into()]; // Native NFC key, not raw UI text.
        assert!(evaluate_capture_policy(&facts).unwrap().skip);
    }
    #[test]
    fn windows_helpers_preserve_name_stem_path_and_exact_matching() {
        let keys = windows_capture_source_keys(Some("NOTEPAD.EXE"), Some(" C:/Apps/KeePass.EXE "));
        assert_eq!(
            keys,
            [
                "notepad",
                "notepad.exe",
                "notepad.exe",
                "keepass",
                "keepass.exe",
                "c:\\apps\\keepass.exe"
            ]
        );
        assert_eq!(normalize_windows_capture_key(" ÉDITOR.EXE "), "éditor.exe");
        let mut facts = input();
        facts.skip_unknown_source = false;
        facts.source_candidate_keys = keys;
        facts.title_match_index = None;
        facts.application_rule_keys = vec![normalize_windows_capture_key("KEEP")];
        assert!(!evaluate_capture_policy(&facts).unwrap().skip);
        facts
            .application_rule_keys
            .push(normalize_windows_capture_key("KEEPASS.EXE"));
        assert_eq!(
            evaluate_capture_policy(&facts).unwrap().matched_rule_index,
            Some(1)
        );
    }
}
