use super::ClipboardCore;
use crate::{
    CoreError, CoreErrorCode, ItemBatchMutationResult, ItemMutation, ItemMutationError,
    ItemMutationOutcome, ItemMutationStatus, Result,
};

impl From<&CoreError> for ItemMutationError {
    fn from(error: &CoreError) -> Self {
        Self {
            code: error.code.as_str().into(),
            message_key: error.message_key().into(),
            recoverable: error.recoverable(),
            message: error.message.clone(),
        }
    }
}

impl ClipboardCore {
    /// The name is item metadata, independent of the captured payload and copy order.
    pub fn rename_item(
        &mut self,
        item_id: impl AsRef<str>,
        title: impl AsRef<str>,
    ) -> Result<crate::ItemManagementResult> {
        let item_id = super::support::normalize_item_id(item_id.as_ref())?;
        let title = title.as_ref().trim();
        let title = if title.is_empty() { None } else { Some(title) };
        let transaction = self.connection.transaction()?;
        let exists: bool = transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM clipboard_items WHERE id = ?1 AND deleted_at_ms IS NULL)",
            [&item_id],
            |row| row.get(0),
        )?;
        if !exists {
            return Ok(crate::ItemManagementResult { affected_count: 0 });
        }
        super::capture::remove_search_index(&transaction, &item_id)?;
        transaction.execute(
            "UPDATE clipboard_items SET custom_title = ?1 WHERE id = ?2",
            rusqlite::params![title, item_id],
        )?;
        super::capture::update_search_index(&transaction, &item_id)?;
        transaction.commit()?;
        Ok(crate::ItemManagementResult { affected_count: 1 })
    }

    /// A bounded sequence of the existing per-item transactions. Already applied
    /// requests are never replayed or rolled back because a later request fails.
    pub fn mutate_items(&mut self, requests: Vec<ItemMutation>) -> Result<ItemBatchMutationResult> {
        if requests.len() > crate::MAX_ITEM_BATCH_SIZE {
            return Err(CoreError::new(
                CoreErrorCode::InvalidInput,
                "at most 200 mutations are allowed",
            ));
        }
        let mut result = ItemBatchMutationResult {
            outcomes: Vec::with_capacity(requests.len()),
            session_fault: false,
            termination_reason: None,
        };
        for (request_index, request) in requests.into_iter().enumerate() {
            if result.session_fault {
                result.outcomes.push(ItemMutationOutcome {
                    request_index,
                    status: ItemMutationStatus::NotAttempted,
                    affected_count: 0,
                    error: None,
                    requires_refresh: false,
                    committed: Some(false),
                });
                continue;
            }
            let operation = match request {
                ItemMutation::Rename { item_id, title } => self.rename_item(item_id, title),
                ItemMutation::Delete { item_id } => self.delete_item(item_id),
                ItemMutation::SetPinboardMembership {
                    item_id,
                    pinboard_id,
                    is_member,
                } => self.set_item_pinboard_membership(item_id, pinboard_id, is_member),
                ItemMutation::RecordCopied { item_id } => self.record_item_copied(item_id),
            };
            let outcome = match operation {
                Ok(management) => ItemMutationOutcome {
                    request_index,
                    status: if management.affected_count > 0 {
                        ItemMutationStatus::Applied
                    } else {
                        ItemMutationStatus::ZeroAffected
                    },
                    affected_count: management.affected_count,
                    error: None,
                    requires_refresh: management.affected_count > 0,
                    committed: Some(management.affected_count > 0),
                },
                Err(error) => {
                    result.session_fault = matches!(
                        error.code,
                        CoreErrorCode::DatabaseUnavailable
                            | CoreErrorCode::MigrationFailed
                            | CoreErrorCode::MigrationChecksumMismatch
                            | CoreErrorCode::RecoveryRequired
                    );
                    let committed = if error
                        .details
                        .get("mutation_committed")
                        .is_some_and(|value| value == "true")
                    {
                        Some(true)
                    } else if error.code == CoreErrorCode::InvalidInput {
                        Some(false)
                    } else {
                        None
                    };
                    let public_error = ItemMutationError::from(&error);
                    if result.session_fault {
                        result.termination_reason = Some(public_error.clone());
                    }
                    ItemMutationOutcome {
                        request_index,
                        status: ItemMutationStatus::Failed,
                        affected_count: 0,
                        error: Some(public_error),
                        requires_refresh: committed != Some(false),
                        committed,
                    }
                }
            };
            result.outcomes.push(outcome);
        }
        Ok(result)
    }
}
