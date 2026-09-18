import { useLayoutEffect, useRef, useState } from "react";

export function CardTitleEditor({ value, placeholder, onSave, onCancel }: {
  value: string;
  placeholder: string;
  onSave: (value: string) => void;
  onCancel: () => void;
}) {
  const [draft, setDraft] = useState(value);
  const input = useRef<HTMLInputElement>(null);
  const finished = useRef(false);
  const composing = useRef(false);
  useLayoutEffect(() => {
    input.current?.focus();
    input.current?.select();
  }, []);
  function finish(save: boolean) {
    if (finished.current) return;
    finished.current = true;
    if (save) onSave(draft);
    else onCancel();
  }
  return <input ref={input} className="card-title-editor" aria-label="重命名卡片"
    value={draft} placeholder={placeholder}
    onChange={(event) => setDraft(event.target.value)}
    onClick={(event) => event.stopPropagation()}
    onDoubleClick={(event) => event.stopPropagation()}
    onContextMenu={(event) => event.stopPropagation()}
    onCompositionStart={() => { composing.current = true; }}
    onCompositionEnd={() => { composing.current = false; }}
    onBlur={() => finish(true)}
    onKeyDown={(event) => {
      event.stopPropagation();
      if (composing.current || event.nativeEvent.isComposing || event.keyCode === 229) return;
      if (event.key === "Enter" || event.key === "Escape") {
        event.preventDefault();
        finish(event.key === "Enter");
      }
    }} />;
}
