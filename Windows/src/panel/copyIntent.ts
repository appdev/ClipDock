import { invoke, isTauri } from "@tauri-apps/api/core";

export type ClipboardCopyResult = {
  status: "written" | "superseded";
  record_warning: string | null;
};

export class CopyIntentController {
  private current = 0;

  begin(): number {
    this.current++;
    return this.current;
  }

  isCurrent(intent: number): boolean {
    return this.current === intent;
  }

  cancel(): number {
    return this.begin();
  }
}

export const panelCopyIntents = new CopyIntentController();
let nativeSession: Promise<number> | undefined;

function copySession(): Promise<number> {
  // A backend-issued epoch makes requests from a disposed/reloaded webview
  // stale without depending on wall-clock ordering or persistent UI state.
  nativeSession ??= invoke<number>("begin_clipboard_copy_session").catch((error) => {
    nativeSession = undefined;
    throw error;
  });
  return nativeSession;
}

export async function copyStoredItem(itemId: string, intentId: number): Promise<ClipboardCopyResult> {
  const sessionId = await copySession();
  if (!panelCopyIntents.isCurrent(intentId)) return { status: "superseded", record_warning: null };
  return invoke<ClipboardCopyResult>("write_clipboard_item", { itemId, sessionId, intentId });
}

export async function copyNativeText(text: string, intentId: number): Promise<ClipboardCopyResult> {
  const sessionId = await copySession();
  if (!panelCopyIntents.isCurrent(intentId)) return { status: "superseded", record_warning: null };
  return invoke<ClipboardCopyResult>("write_clipboard_text_intent", { text, sessionId, intentId });
}

export function cancelPendingClipboardCopy(): void {
  const intentId = panelCopyIntents.cancel();
  if (isTauri()) void copySession().then((sessionId) => invoke("cancel_clipboard_copy", { sessionId, intentId })).catch(() => undefined);
}
