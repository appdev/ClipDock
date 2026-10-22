import { useEffect, useState, useSyncExternalStore } from "react";
import { isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { HistoryController, type HistoryScope } from "./historyController";
import { historyRepository } from "./panelStore";

export function useHistory(scope: HistoryScope) {
  const [controller] = useState(() => new HistoryController(historyRepository));
  const [captureError, setCaptureError] = useState<string | null>(null);
  const state = useSyncExternalStore(controller.subscribe, controller.snapshot);
  useEffect(() => { controller.setScope(scope); }, [controller, scope.itemType, scope.pinboardId, scope.searchText]);
  useEffect(() => {
    if (!isTauri()) return;
    let cancelled = false;
    const unlisteners: Array<() => void> = [];
    void listen<string>("clipboard-capture-error", () => setCaptureError("剪贴板采集失败；新复制内容时会再次尝试"))
      .then((stop) => { if (cancelled) stop(); else unlisteners.push(stop); }).catch(() => undefined);
    void listen<{ revision: number }>("history-changed", (event) => { setCaptureError(null); controller.invalidate(event.payload.revision); })
      .then((stop) => {
        if (cancelled) { stop(); return; }
        unlisteners.push(stop);
        controller.start();
      }).catch(() => { if (!cancelled) controller.start(); });
    const onFocus = () => controller.refresh();
    window.addEventListener("focus", onFocus);
    return () => { cancelled = true; unlisteners.forEach((stop) => stop()); window.removeEventListener("focus", onFocus); controller.stop(); };
  }, [controller]);
  return { ...state, controller, captureError };
}
