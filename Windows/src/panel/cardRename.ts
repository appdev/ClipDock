import { invoke, isTauri } from "@tauri-apps/api/core";

export function normalizedCardTitle(value: string): string | null {
  return value.trim() || null;
}

export function matchesRenameShortcut(event: Pick<KeyboardEvent, "key" | "ctrlKey" | "metaKey" | "altKey" | "shiftKey" | "isComposing">): boolean {
  if (event.isComposing || event.altKey || event.shiftKey || event.metaKey) return false;
  return (event.key === "F2" && !event.ctrlKey) || (event.ctrlKey && event.key.toLowerCase() === "r");
}

export async function persistCardTitle(id: string, title: string | null): Promise<void> {
  if (!isTauri()) return;
  const result = await invoke<{ affected_count: number }>("rename_clipboard_item", { itemId: id, title: title ?? "" });
  if (result.affected_count !== 1) throw new Error("Clipboard item no longer exists");
}

// Serialize writes per card. Only the newest edit may replace the visible title;
// failures roll back to the last successful write, including earlier queued edits.
export class CardRenameQueue {
  private pending = new Map<string, { tail: Promise<void>; confirmed: string | null; revision: number }>();

  constructor(private persist: typeof persistCardTitle) {}

  save(id: string, previous: string | null, next: string | null,
    update: (title: string | null) => void, failed: () => void): Promise<void> {
    const state = this.pending.get(id) ?? { tail: Promise.resolve(), confirmed: previous, revision: 0 };
    this.pending.set(id, state);
    const revision = ++state.revision;
    update(next);
    state.tail = state.tail.then(async () => {
      try {
        await this.persist(id, next);
        state.confirmed = next;
      } catch {
        if (revision === state.revision) {
          update(state.confirmed);
          failed();
        }
      } finally {
        if (revision === state.revision) this.pending.delete(id);
      }
    });
    return state.tail;
  }
}
