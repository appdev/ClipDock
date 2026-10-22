import { useCallback, useEffect, useRef, useState, type RefObject } from "react";
import { CARD_GAP, CARD_INSET, scrollForIndex, virtualRange } from "./virtualRail";

export function useVirtualRail(rail: RefObject<HTMLDivElement | null>, count: number, side: number) {
  const [viewport, setViewport] = useState({ left: 0, width: 0 });
  const previousSide = useRef(side);
  const update = useCallback(() => {
    const node = rail.current;
    if (node) setViewport((old) => old.left === node.scrollLeft && old.width === node.clientWidth
      ? old : { left: node.scrollLeft, width: node.clientWidth });
  }, [rail]);
  useEffect(() => {
    const node = rail.current;
    if (!node) return;
    let frame = 0;
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(() => { frame = 0; update(); });
    };
    const observer = new ResizeObserver(update);
    observer.observe(node);
    node.addEventListener("scroll", onScroll, { passive: true });
    update();
    return () => { observer.disconnect(); node.removeEventListener("scroll", onScroll); cancelAnimationFrame(frame); };
  }, [rail, update]);
  useEffect(() => {
    const node = rail.current;
    if (node && previousSide.current !== side) {
      const position = Math.max(0, node.scrollLeft - CARD_INSET) / (previousSide.current + CARD_GAP);
      node.scrollLeft = node.scrollLeft === 0 ? 0 : CARD_INSET + position * (side + CARD_GAP);
    }
    previousSide.current = side;
    update();
  }, [side, count, rail, update]);
  const scrollToIndex = useCallback((index: number) => {
    const node = rail.current;
    if (!node || index < 0) return;
    node.scrollLeft = scrollForIndex(index, side, node.scrollLeft, node.clientWidth);
    update();
  }, [rail, side, update]);
  return { ...virtualRange(count, side, viewport.left, viewport.width), scrollToIndex };
}
