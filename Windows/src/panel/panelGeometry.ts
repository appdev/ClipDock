export const panelGeometry = {
  defaultHeight: 320,
  minimumHeight: 260,
  maximumHeightRatio: 0.3,
  outerMargin: 10,
  resizeHandleHeight: 16,
  controlBarHeight: 52,
  sectionSpacing: 12,
  padding: 22,
  horizontalContentInset: 22,
  defaultItemSide: 218,
  compactItemSide: 156,
  cardHeaderHeight: 48,
  cardInset: 12,
  cardFooterHeight: 17,
  cardCornerRadius: 15,
  innerCornerRadius: 8,
  sourceIconSize: 54,
  linkPreviewHeight: 84,
  panelBackgroundCornerRadius: 26
} as const;

export type PanelFrame = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export function clampedPanelHeight(height: number, screenHeight: number): number {
  const maximum = Math.max(
    panelGeometry.minimumHeight,
    screenHeight * panelGeometry.maximumHeightRatio
  );
  return Math.min(Math.max(height, panelGeometry.minimumHeight), maximum);
}

export function resizedPanelHeight(
  startHeight: number,
  deltaY: number,
  screenHeight: number
): number {
  return clampedPanelHeight(startHeight + deltaY, screenHeight);
}

export function bottomPanelFrame(
  screenFrame: PanelFrame,
  preferredHeight: number
): PanelFrame {
  const height = clampedPanelHeight(preferredHeight, screenFrame.height);
  return {
    x: screenFrame.x + panelGeometry.outerMargin,
    y: screenFrame.y + panelGeometry.outerMargin,
    width: Math.max(0, screenFrame.width - panelGeometry.outerMargin * 2),
    height
  };
}

export function itemSideLength(panelHeight: number): number {
  const available = Math.max(
    panelGeometry.compactItemSide,
    panelHeight -
      panelGeometry.controlBarHeight -
      panelGeometry.sectionSpacing -
      panelGeometry.padding
  );
  return Math.min(panelGeometry.defaultItemSide, available);
}
