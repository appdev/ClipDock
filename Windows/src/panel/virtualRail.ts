export const CARD_GAP = 24;
export const CARD_INSET = 22;
export const CARD_OVERSCAN = 2;

/** Keep an active editor mounted when it scrolls outside the visible window. */
export function mountedCardIndices(count: number, start: number, end: number, editingIndex: number): number[] {
  const indices = Array.from({ length: Math.max(0, end - start) }, (_, offset) => start + offset);
  if (editingIndex >= 0 && editingIndex < count && !indices.includes(editingIndex)) {
    indices.push(editingIndex);
    indices.sort((a, b) => a - b);
  }
  return indices;
}

export function railWidth(count: number, side: number): number {
  return CARD_INSET * 2 + Math.max(0, count) * side + Math.max(0, count - 1) * CARD_GAP;
}

export function cardOffset(index: number, side: number): number {
  return CARD_INSET + index * (side + CARD_GAP);
}

export function virtualRange(count: number, side: number, scrollLeft: number, viewport: number) {
  if (count <= 0 || side <= 0 || viewport <= 0) return { start: 0, end: 0 };
  const pitch = side + CARD_GAP;
  const first = Math.max(0, Math.floor((scrollLeft - CARD_INSET) / pitch));
  const end = Math.min(count, Math.ceil((scrollLeft + viewport - CARD_INSET) / pitch) + CARD_OVERSCAN);
  return { start: Math.min(count, Math.max(0, first - CARD_OVERSCAN)), end: Math.max(0, end) };
}

export function scrollForIndex(index: number, side: number, scrollLeft: number, viewport: number) {
  const left = cardOffset(index, side);
  if (left < scrollLeft + CARD_INSET) return Math.max(0, left - CARD_INSET);
  if (left + side > scrollLeft + viewport - CARD_INSET) return Math.max(0, left + side + CARD_INSET - viewport);
  return scrollLeft;
}
