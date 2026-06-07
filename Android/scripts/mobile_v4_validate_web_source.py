#!/usr/bin/env python3
"""Generate and validate ClipDock mobile V4 pixel-locked WebView assets."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile

ROOT = Path(__file__).resolve().parents[2]
ANDROID_ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = ANDROID_ROOT / "ui-web" / "mobile-v4"
SRC_ROOT = WEB_ROOT / "src"
GENERATED_ROOT = WEB_ROOT / "generated"
REFERENCE_PATH = WEB_ROOT / "reference" / "clipdock-mobile-complete-design-v4.html"
REFERENCE_ASSETS_ROOT = REFERENCE_PATH.parent / "assets"
REFERENCE_IMAGE_ASSET = REFERENCE_ASSETS_ROOT / "ui-review-screenshot.png"
ASSET_ROOT = ANDROID_ROOT / "app" / "src" / "main" / "assets" / "clipdock-mobile-v4"
CONFIG_PATH = ANDROID_ROOT / "qa" / "mobile-v4-pixel-config.json"
ARTIFACT_ROOT = ROOT / ".codex" / "artifacts" / "android-mobile-v4-pixel"
VENV_PYTHON = ROOT / ".codex" / "venvs" / "android-mobile-v4-pixel" / "bin" / "python"
GENERATOR_VERSION = 5
INNER_CROP = (10, 10, 380, 834)
SELF_REFERENTIAL_FILES = {"manifest.json", "provenance.json"}
HISTORY_CARD_CONTRACT = {
  "text": {"stable_id": "qa-ready-text", "selectors": [".clip-content"]},
  "image": {"stable_id": "qa-remote-image", "selectors": [".clip-content", ".image-thumb", ".image-thumb img", ".media-name"]},
  "file": {"stable_id": "qa-ready-file", "selectors": [".clip-content", ".file-icon", ".file-copy", ".file-path"]},
  "link": {"stable_id": "qa-link", "selectors": [".clip-content", ".link-domain", ".link-copy"]},
  "color": {"stable_id": "qa-color", "selectors": [".clip-content", ".color-swatch", ".color-values"]},
}
REQUIRED_SOURCE_FILES = [
  SRC_ROOT / "index.html",
  SRC_ROOT / "styles.css",
  SRC_ROOT / "app.js",
  SRC_ROOT / "schema.json",
  WEB_ROOT / "manifest.json",
  REFERENCE_PATH,
  REFERENCE_IMAGE_ASSET,
  CONFIG_PATH,
]
FORBIDDEN_RESOURCE_PATTERNS = [
  re.compile(r"\b(?:src|href)\s*=\s*[\"']https?://", re.IGNORECASE),
  re.compile(r"url\(\s*[\"']?https?://", re.IGNORECASE),
  re.compile(r"@import\s+", re.IGNORECASE),
  re.compile(r"<link\b[^>]*rel=[\"']?stylesheet", re.IGNORECASE),
]


def ensure_playwright_runtime() -> None:
  try:
    import PIL  # noqa: F401
    import playwright  # noqa: F401
    return
  except ModuleNotFoundError:
    if VENV_PYTHON.is_file() and os.environ.get("CLIPDOCK_MOBILE_V4_VENV_BOOTSTRAPPED") != "1":
      os.environ["CLIPDOCK_MOBILE_V4_VENV_BOOTSTRAPPED"] = "1"
      os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])
    raise


def sha256_bytes(data: bytes) -> str:
  return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
  digest = hashlib.sha256()
  with path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
      digest.update(chunk)
  return digest.hexdigest()


def json_sha(data: object) -> str:
  return sha256_bytes(json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())


def write_json(path: Path, data: object) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def tree_sha(root: Path, *, exclude_self_referential: bool = False) -> str:
  digest = hashlib.sha256()
  for path in sorted(p for p in root.rglob("*") if p.is_file()):
    if exclude_self_referential and path.name in SELF_REFERENTIAL_FILES:
      continue
    digest.update(path.relative_to(root).as_posix().encode())
    digest.update(b"\0")
    data = path.read_bytes()
    if exclude_self_referential and path.suffix == ".json" and "semantics-reference" in path.parts:
      payload = json.loads(data.decode("utf-8"))
      payload.pop("runtime_asset_sha256", None)
      data = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    digest.update(data)
    digest.update(b"\0")
  return digest.hexdigest()


def source_tree_sha() -> str:
  digest = hashlib.sha256()
  for path in sorted([*SRC_ROOT.rglob("*"), REFERENCE_PATH, *REFERENCE_ASSETS_ROOT.rglob("*"), WEB_ROOT / "manifest.json", CONFIG_PATH]):
    if not path.is_file():
      continue
    digest.update(path.relative_to(ROOT).as_posix().encode())
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")
  return digest.hexdigest()


def assert_required_files() -> None:
  missing = [str(path) for path in REQUIRED_SOURCE_FILES if not path.is_file()]
  if missing:
    raise SystemExit("Missing mobile V4 web source files:\n" + "\n".join(missing))


def assert_no_network_resources() -> None:
  for path in [SRC_ROOT / "index.html", SRC_ROOT / "styles.css", SRC_ROOT / "app.js", REFERENCE_PATH]:
    text = path.read_text(encoding="utf-8")
    for pattern in FORBIDDEN_RESOURCE_PATTERNS:
      if path.name == "index.html" and pattern.pattern.startswith("<link"):
        continue
      matches = pattern.findall(text)
      if matches:
        raise SystemExit(f"Forbidden external resource marker in {path}: {matches[:3]}")
  index = (SRC_ROOT / "index.html").read_text(encoding="utf-8")
  if "href=\"styles.css" not in index:
    raise SystemExit("src/index.html must use the local styles.css stylesheet")


def playwright_metadata() -> dict[str, str | None]:
  try:
    version = subprocess.check_output([sys.executable, "-m", "playwright", "--version"], text=True).strip()
  except Exception:
    version = None
  return {
    "python": sys.executable,
    "python_version": platform.python_version(),
    "playwright_version": version,
    "chromium": "playwright.chromium",
  }


def screen_config() -> tuple[list[str], list[str], int, int]:
  config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
  size = config["screen_size"]
  return config["screens"], config["themes"], int(size["width"]), int(size["height"])


def expected_action_ids(screen_id: str) -> list[str]:
  mapping = {
    "history": [
      "copyItem:qa-ready-text",
      "openItemDetail:qa-ready-text",
      "openItemDetail:qa-remote-image",
      "openItemDetail:qa-ready-file",
      "openItemDetail:qa-link",
      "openItemDetail:qa-color",
      "selectDestination:devices",
      "selectDestination:files",
      "selectDestination:settings",
      "syncNow",
    ],
    "devices": ["selectDestination:history", "selectDestination:files", "selectDestination:settings"],
    "files": [
      "openItemDetail:qa-remote-image",
      "openItemDetail:qa-ready-file",
      "selectDestination:history",
      "selectDestination:devices",
      "selectDestination:settings",
    ],
    "settings": [
      "openSettingsDetail:keep_alive",
      "openSettingsDetail:floating_ball",
      "setP2pEnabled",
      "setWifiOnly",
      "selectDestination:history",
      "selectDestination:devices",
      "selectDestination:files",
    ],
    "keep_alive": [
      "closeSettingsDetail",
      "selectDestination:history",
      "selectDestination:devices",
      "selectDestination:files",
      "selectDestination:settings",
    ],
    "floating_ball": [
      "closeSettingsDetail",
      "setOverlayEnabled",
      "setOverlaySize",
      "setOverlayOpacity",
      "setOverlayVerticalFraction",
      "setOverlaySnapEdge",
      "selectDestination:history",
      "selectDestination:devices",
      "selectDestination:files",
      "selectDestination:settings",
    ],
    "item_detail_text": ["closeDetail", "copyItem:qa-ready-text", "showDeleteConfirm:qa-ready-text"],
    "remote_asset_sheet": [
      "downloadAndCopy:qa-remote-image",
      "downloadToCache:qa-remote-image",
      "copyThumbnail:qa-remote-image",
      "hideRemoteRetrieval",
    ],
    "delete_confirm": ["removeLocalCache:qa-ready-text", "deleteSyncRecord:qa-ready-text", "hideDeleteConfirm"],
  }
  return mapping[screen_id]


async def assert_history_card_contract(page) -> None:
  errors = await page.evaluate(
    """
({ contract }) => {
  const requiredTypes = Object.keys(contract);
  const errors = [];
  function rect(element) {
    const value = element.getBoundingClientRect();
    return { left: value.left, top: value.top, right: value.right, bottom: value.bottom, width: value.width, height: value.height };
  }
  function overlaps(a, b) {
    return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
  }
  for (const theme of ["light", "dark"]) {
    const grid = document.querySelector(`.board.theme-${theme} .panel:nth-of-type(1) .history-grid`);
    if (!grid) {
      errors.push(`${theme}: missing history grid`);
      continue;
    }
    if (grid.querySelector(".clip-title,.clip-sub")) {
      errors.push(`${theme}: history cards still contain .clip-title or .clip-sub`);
    }
    const cards = [...grid.querySelectorAll(".clip-card[data-card-type]")];
    const types = cards.map((card) => card.dataset.cardType);
    if (types.join(",") !== requiredTypes.join(",")) {
      errors.push(`${theme}: card types ${types.join(",")} != ${requiredTypes.join(",")}`);
    }
    const stableIds = cards.map((card) => card.dataset.stableId || "");
    const uniqueStableIds = new Set(stableIds);
    if (uniqueStableIds.size !== stableIds.length) {
      errors.push(`${theme}: duplicate history card data-stable-id`);
    }
    const firstCardRect = cards[0] ? rect(cards[0]) : null;
    const colorCard = cards.find((card) => card.dataset.cardType === "color");
    if (firstCardRect && colorCard) {
      const colorRect = rect(colorCard);
      if (colorRect.width > firstCardRect.width * 1.2 || Math.abs(colorRect.height - firstCardRect.height) > 2) {
        errors.push(`${theme}/color: color card must use the same item card dimensions`);
      }
    }
    for (const card of cards) {
      const type = card.dataset.cardType;
      const expected = contract[type];
      if (!expected) {
        errors.push(`${theme}: unexpected card type ${type}`);
        continue;
      }
      if (card.dataset.stableId !== expected.stable_id) {
        errors.push(`${theme}/${type}: stable id ${card.dataset.stableId || "<missing>"} != ${expected.stable_id}`);
      }
      const footer = card.querySelector(".clip-footer");
      if (type !== "text" && footer) {
        errors.push(`${theme}/${type}: .clip-footer is only allowed on the text card`);
      }
      const body = card.querySelector(".clip-body");
      if (!body) {
        errors.push(`${theme}/${type}: missing .clip-body`);
        continue;
      }
      const contents = [...card.querySelectorAll(".clip-content")];
      if (contents.length !== 1) {
        errors.push(`${theme}/${type}: expected one .clip-content, found ${contents.length}`);
        continue;
      }
      for (const selector of expected.selectors) {
        if (!card.querySelector(selector)) errors.push(`${theme}/${type}: missing ${selector}`);
      }
      const content = contents[0];
      const contentStyle = getComputedStyle(content);
      if (contentStyle.overflow === "visible") {
        errors.push(`${theme}/${type}: .clip-content is not clipped`);
      }
      const contentBorderWidths = [
        contentStyle.borderTopWidth,
        contentStyle.borderRightWidth,
        contentStyle.borderBottomWidth,
        contentStyle.borderLeftWidth,
      ].map((value) => Number.parseFloat(value || "0"));
      if (contentBorderWidths.some((value) => Number.isFinite(value) && value > 0)) {
        errors.push(`${theme}/${type}: content area must not have an inner border`);
      }
      const decorativeBackgroundAllowed = type === "color";
      if (!decorativeBackgroundAllowed && contentStyle.backgroundColor !== "rgba(0, 0, 0, 0)") {
        errors.push(`${theme}/${type}: content area must not have a separate inner background`);
      }
      if (!decorativeBackgroundAllowed && contentStyle.backgroundImage !== "none") {
        errors.push(`${theme}/${type}: content area must not have a separate inner background image`);
      }
      if (type === "text") {
        if (!footer) {
          errors.push(`${theme}/text: text card must keep the compact footer`);
        } else {
          const copyLabel = footer.querySelector(".copy-chip")?.textContent.trim() || "";
          const charLabel = footer.querySelector(".char-count")?.textContent.trim() || "";
          if (copyLabel !== "复制") errors.push(`${theme}/text: .copy-chip label ${copyLabel || "<missing>"} != 复制`);
          if (charLabel !== "64 字符") errors.push(`${theme}/text: .char-count label ${charLabel || "<missing>"} != 64 字符`);
        }
        const clamp = Number.parseInt(contentStyle.webkitLineClamp || "0", 10);
        if (!Number.isFinite(clamp) || clamp < 2) errors.push(`${theme}/text: missing multiline line clamp`);
        const weight = Number.parseInt(contentStyle.fontWeight || "0", 10);
        if (!Number.isFinite(weight) || weight >= 600) errors.push(`${theme}/text: text content must use regular body weight below 600`);
        if (!content.textContent.includes("发布说明") || card.querySelector(".clip-content .clip-title,.clip-content .clip-sub")) {
          errors.push(`${theme}/text: text content is not a single unified body`);
        }
      }
      if (type === "image") {
        const image = card.querySelector(".image-thumb img");
        if (!image || !image.getAttribute("src")?.includes("assets/ui-review-screenshot.png")) {
          errors.push(`${theme}/image: missing real local image asset`);
        } else if (!image.complete || image.naturalWidth <= 0 || image.naturalHeight <= 0) {
          errors.push(`${theme}/image: real image asset did not load`);
        }
        if (getComputedStyle(image).objectFit !== "contain") {
          errors.push(`${theme}/image: image preview must contain the full real image`);
        }
        const badge = card.querySelector(".media-name");
        const badgeText = badge?.textContent || "";
        if (!/\\d+\\s*×\\s*\\d+/.test(badgeText)) {
          errors.push(`${theme}/image: image card must show a dimension badge`);
        }
        const badgeFontSize = badge ? Number.parseFloat(getComputedStyle(badge).fontSize || "0") : NaN;
        if (!Number.isFinite(badgeFontSize) || badgeFontSize > 12) {
          errors.push(`${theme}/image: image dimension badge font must be compact (<= 12px)`);
        }
        const bodyBackground = getComputedStyle(body).backgroundImage || "";
        if (!bodyBackground.includes("linear-gradient")) {
          errors.push(`${theme}/image: image card must use the checkerboard content surface`);
        }
        const thumb = card.querySelector(".image-thumb");
        const before = getComputedStyle(thumb, "::before").content;
        const after = getComputedStyle(thumb, "::after").content;
        if (before !== "none" || after !== "none") {
          errors.push(`${theme}/image: image thumb still uses pseudo-element illustration`);
        }
        const bg = getComputedStyle(thumb).backgroundImage || "";
        if (bg.includes("gradient")) {
          errors.push(`${theme}/image: image thumb still uses gradient illustration`);
        }
      }
      if (type === "file") {
        const pathText = card.querySelector(".file-path")?.textContent || "";
        if (!pathText.includes("/") || !pathText.includes("Server-config.txt")) {
          errors.push(`${theme}/file: file card does not show a path`);
        }
        if (card.querySelector(".file-copy strong")) {
          errors.push(`${theme}/file: file card still shows a title`);
        }
        if (/text\\/plain|\\bKB\\b|已缓存|TXT/.test(card.textContent || "")) {
          errors.push(`${theme}/file: file card still shows metadata instead of icon plus path`);
        }
      }
      if (type === "color") {
        const hexText = card.querySelector(".color-values strong")?.textContent || "";
        if (hexText.trim() !== "#7C3AED") {
          errors.push(`${theme}/color: color card must show the centered #7C3AED value`);
        }
        const swatchColor = getComputedStyle(card.querySelector(".color-swatch")).backgroundColor;
        if (swatchColor !== "rgb(124, 58, 237)") {
          errors.push(`${theme}/color: color card swatch does not match #7C3AED`);
        }
      }
      const cardRect = rect(card);
      const bodyRect = rect(body);
      const contentRect = rect(content);
      if (contentRect.width <= 0 || contentRect.height <= 0) {
        errors.push(`${theme}/${type}: invalid content bounds`);
      }
      if (contentRect.left < cardRect.left || contentRect.right > cardRect.right || contentRect.top < cardRect.top || contentRect.bottom > cardRect.bottom) {
        errors.push(`${theme}/${type}: content escapes card bounds`);
      }
      if (
        Math.abs(contentRect.left - bodyRect.left) > 1 ||
        Math.abs(contentRect.top - bodyRect.top) > 1 ||
        Math.abs(contentRect.right - bodyRect.right) > 1 ||
        Math.abs(contentRect.bottom - bodyRect.bottom) > 1
      ) {
        errors.push(`${theme}/${type}: content does not fill the area below header`);
      }
    }
  }
  return errors;
}
    """,
    {"contract": HISTORY_CARD_CONTRACT},
  )
  if errors:
    raise SystemExit("History card contract failed:\n" + "\n".join(f"- {error}" for error in errors))


EXTRACT_JS = r"""
({ theme, screenId, index, visualSha, sourceSha, expectedWidth, expectedHeight }) => {
  function ensureDarkBoard() {
    if (document.querySelector(".board.theme-dark")) return;
    const lightBoard = document.querySelector(".board.theme-light");
    if (!lightBoard) return;
    const darkBoard = lightBoard.cloneNode(true);
    darkBoard.classList.remove("theme-light");
    darkBoard.classList.add("theme-dark");
    darkBoard.dataset.mode = "dark";
    const title = darkBoard.querySelector(".board-header h1");
    if (title) title.textContent = "ClipDock Android Mobile UI V4 Dark";
    const description = darkBoard.querySelector(".board-header p");
    if (description) {
      description.textContent =
        "深色模式与浅色模式保持同一信息架构和交互状态：历史、设备、文件、设置、保活权限、悬浮球、item 详情、远端取回和删除确认均同步展示。";
    }
    const version = darkBoard.querySelector(".version");
    if (version) version.textContent = "Dark mode review · 2026-06-04";
    document.body.appendChild(darkBoard);
  }
  ensureDarkBoard();
  const panel = document.querySelector(`.board.theme-${theme} .panel:nth-of-type(${index})`);
  const phone = panel && panel.querySelector(".phone");
  const screen = panel && panel.querySelector(".screen");
  if (!panel || !phone || !screen) throw new Error(`Missing panel for ${theme}/${screenId}`);
  const phoneRect = phone.getBoundingClientRect();
  const origin = { x: phoneRect.left + 10, y: phoneRect.top + 10 };
  const inner = { x: 0, y: 0, width: expectedWidth, height: expectedHeight };
  const routeToNav = {
    history: "历史",
    devices: "设备",
    files: "文件",
    settings: "设置",
    keep_alive: "设置",
    floating_ball: "设置",
    item_detail_text: null,
    remote_asset_sheet: null,
    delete_confirm: null,
  };
  const routeToSelectedStableId = {
    history: null,
    devices: null,
    files: null,
    settings: null,
    keep_alive: null,
    floating_ball: null,
    item_detail_text: "qa-ready-text",
    remote_asset_sheet: "qa-remote-image",
    delete_confirm: "qa-ready-text",
  };
  const hotzones = [];
  let z = 1;

  function text(element) {
    return (element && element.textContent || "").replace(/\s+/g, " ").trim();
  }
  function bounds(element) {
    const rect = element.getBoundingClientRect();
    return {
      x: Math.round(rect.left - origin.x),
      y: Math.round(rect.top - origin.y),
      width: Math.round(rect.width),
      height: Math.round(rect.height),
    };
  }
  function intersects(rect) {
    return rect.width > 0 && rect.height > 0 && rect.x < expectedWidth && rect.y < expectedHeight && rect.x + rect.width > 0 && rect.y + rect.height > 0;
  }
  function actionId(action, detail) {
    if (detail.stable_id) return `${action}:${detail.stable_id}`;
    if ((action === "selectDestination" || action === "openSettingsDetail") && detail.route) return `${action}:${detail.route}`;
    return action;
  }
  function add(element, action, detail = {}) {
    if (!element) return;
    const rect = bounds(element);
    if (!intersects(rect)) return;
    const zone = {
      stable_id: detail.stable_id || actionId(action, detail),
      action,
      action_id: actionId(action, detail),
      role: detail.role || "button",
      label: detail.label || text(element) || action,
      bounds: rect,
      z_order: detail.z_order || z++,
      route: screenId,
      theme,
      active_sheet: screenId === "remote_asset_sheet" ? "remote_retrieval" : screenId === "delete_confirm" ? "delete_confirm" : null,
      selected_nav: routeToNav[screenId],
      enabled: detail.enabled !== false,
      anchors: detail.anchors || [],
      bridge: {
        version: 1,
        action,
      },
    };
    if (detail.stable_id) zone.bridge.stableId = detail.stable_id;
    if (detail.route) zone.bridge.route = detail.route;
    if (detail.sheet) zone.bridge.sheet = detail.sheet;
    if (detail.setting) zone.bridge.setting = detail.setting;
    if (detail.value !== undefined) zone.bridge.value = detail.value;
    hotzones.push(zone);
  }
  function routeForNav(element) {
    const label = text(element);
    if (label === "设备") return "devices";
    if (label === "文件") return "files";
    if (label === "设置") return "settings";
    return "history";
  }

  const topIcons = [...panel.querySelectorAll(".icon-btn")];
  if (screenId === "item_detail_text") {
    add(topIcons[0], "closeDetail", { label: "返回" });
  } else if (screenId === "remote_asset_sheet") {
    add(topIcons[0], "hideRemoteRetrieval", { label: "关闭远端取回" });
  } else if (screenId === "delete_confirm") {
    add(topIcons[0], "hideDeleteConfirm", { label: "取消删除" });
  } else if (screenId === "keep_alive" || screenId === "floating_ball") {
    add(topIcons[0], "closeSettingsDetail", { label: "返回设置" });
  } else if (screenId === "history") {
    add(topIcons[0], "syncNow", { label: "立即同步" });
  }

  panel.querySelectorAll(".nav-item").forEach((element) => {
    const route = routeForNav(element);
    if (route !== screenId) add(element, "selectDestination", { route, label: text(element) });
  });

  if (screenId === "history") {
    panel.querySelectorAll(".history-grid .clip-card[data-stable-id]").forEach((element) => {
      add(element, "openItemDetail", { stable_id: element.dataset.stableId, label: `打开 ${text(element)}` });
    });
    add(panel.querySelector(".history-grid .text-card .copy-chip"), "copyItem", {
      stable_id: "qa-ready-text",
      label: "复制",
      role: "button",
      z_order: 200,
      anchors: [".text-card", ".copy-chip"],
    });
  }
  if (screenId === "files") {
    const rows = [...panel.querySelectorAll(".row-card")];
    add(rows[0], "openItemDetail", { stable_id: "qa-remote-image", label: text(rows[0]) || "打开远端图片" });
    add(rows[1], "openItemDetail", { stable_id: "qa-ready-file", label: text(rows[1]) || "打开本机文件" });
  }
  if (screenId === "settings") {
    panel.querySelectorAll(".setting-row").forEach((element) => {
      const label = text(element);
      if (label.includes("P2P")) add(element, "setP2pEnabled", { setting: "p2p_enabled", value: false, label });
      else if (label.includes("保活权限")) add(element, "openSettingsDetail", { route: "keep_alive", label });
      else if (label.includes("悬浮球")) add(element, "openSettingsDetail", { route: "floating_ball", label });
      else if (label.includes("Wi")) add(element, "setWifiOnly", { setting: "wifi_only", value: false, label });
    });
  }
  if (screenId === "floating_ball") {
    panel.querySelectorAll(".setting-row").forEach((element) => {
      const label = text(element);
      if (label.includes("启用悬浮球")) add(element, "setOverlayEnabled", { setting: "overlay_enabled", value: false, label });
      else if (label.includes("点击动作")) add(element, "setOverlayVerticalFraction", { setting: "overlay_vertical_fraction", value: 0.5, label });
      else if (label.includes("停靠边缘")) add(element, "setOverlaySnapEdge", { setting: "overlay_snap_edge", value: "left", label });
    });
    const cards = [...panel.querySelectorAll(".card")];
    const sizeCard = cards.find((element) => text(element).includes("尺寸"));
    const opacityCard = cards.find((element) => text(element).includes("透明度"));
    const snapCard = cards.find((element) => text(element).includes("停靠方向"));
    add(sizeCard, "setOverlaySize", { setting: "overlay_size", value: 64, label: text(sizeCard) });
    add(opacityCard, "setOverlayOpacity", { setting: "overlay_opacity", value: 78, label: text(opacityCard) });
    add(snapCard, "setOverlaySnapEdge", { setting: "overlay_snap_edge", value: "left", label: text(snapCard) });
  }
  if (screenId === "item_detail_text") {
    add(panel.querySelector(".primary-action"), "copyItem", { stable_id: "qa-ready-text", label: "复制" });
    const dockActions = [...panel.querySelectorAll(".dock-action")];
    add(dockActions[dockActions.length - 1], "showDeleteConfirm", { stable_id: "qa-ready-text", sheet: "delete_confirm", label: "删除" });
  }
  if (screenId === "remote_asset_sheet") {
    panel.querySelectorAll(".sheet-action").forEach((element, i) => {
      const action = i === 0 ? "downloadAndCopy" : i === 1 ? "downloadToCache" : "copyThumbnail";
      add(element, action, { stable_id: "qa-remote-image", sheet: "remote_retrieval", label: text(element), z_order: 100 + i });
    });
  }
  if (screenId === "delete_confirm") {
    panel.querySelectorAll(".confirm-button").forEach((element, i) => {
      const action = i === 0 ? "removeLocalCache" : i === 1 ? "deleteSyncRecord" : "hideDeleteConfirm";
      add(element, action, {
        stable_id: i < 2 ? "qa-ready-text" : undefined,
        sheet: "delete_confirm",
        label: text(element),
        enabled: i !== 0,
        z_order: 100 + i,
      });
    });
  }

  const visibleTexts = [...new Set([...panel.querySelectorAll(".phone *")].map(text).filter(Boolean))];
  const keyBounds = { screen: inner };
  panel.querySelectorAll(".screen-title,.clip-card,.row-card,.action-dock,.bottom-sheet,.confirm-sheet,.setting-row,.card").forEach((element) => {
    const label = text(element).slice(0, 64) || element.className;
    const rect = bounds(element);
    if (intersects(rect)) keyBounds[label] = rect;
  });
  return {
    screen_id: screenId,
    theme,
    route: screenId,
    active_sheet: screenId === "remote_asset_sheet" ? "remote_retrieval" : screenId === "delete_confirm" ? "delete_confirm" : null,
    selected_nav: routeToNav[screenId],
    selected_stable_id: routeToSelectedStableId[screenId],
    visible_texts: visibleTexts,
    anchors: hotzones.map((zone) => ({ action_id: zone.action_id, stable_id: zone.stable_id, bounds: zone.bounds })),
    bridge_action_ids: [...new Set(hotzones.map((zone) => zone.action_id))],
    enabled_states: Object.fromEntries(hotzones.map((zone) => [zone.action_id, zone.enabled])),
    focus_order: hotzones.map((zone) => zone.action_id),
    aria_labels: hotzones.map((zone) => zone.label),
    touch_targets_px: Object.fromEntries(hotzones.map((zone) => [zone.action_id, zone.bounds])),
    key_bounds_px: keyBounds,
    computed: { screen: { bounds: inner } },
    sheet_order: hotzones.filter((zone) => zone.active_sheet).map((zone) => ({ action_id: zone.action_id, z_order: zone.z_order })),
    source_sha256: sourceSha,
    runtime_asset_sha256: null,
    visual_png_sha256: visualSha,
    hotzones_sha256: null,
    runtime_dom_source: "playwright-reference-dom",
    semantic_source: "dom-extracted-reference-and-production-hotzones",
    fallback: false,
    hotzones,
  };
}
"""


async def render_generated_assets(output_root: Path, *, artifact_reference_root: Path | None = None) -> dict[str, object]:
  ensure_playwright_runtime()
  from PIL import Image
  from playwright.async_api import async_playwright

  screens, themes, expected_width, expected_height = screen_config()
  source_sha = source_tree_sha()
  design_sha = sha256(REFERENCE_PATH)
  output_root.mkdir(parents=True, exist_ok=True)
  generated_reference = output_root / "reference"
  generated_semantics = output_root / "semantics-reference"
  png_hashes: dict[str, dict[str, str]] = {}
  semantic_hashes: dict[str, dict[str, str]] = {}
  all_hotzones: dict[str, dict[str, list[dict[str, object]]]] = {}
  all_semantics: dict[str, dict[str, dict[str, object]]] = {}

  async with async_playwright() as playwright:
    browser = await playwright.chromium.launch()
    page = await browser.new_page(viewport={"width": 4200, "height": 2600}, device_scale_factor=1)
    await page.goto(REFERENCE_PATH.resolve().as_uri())
    await page.wait_for_selector(".board.theme-light .panel .phone")
    await page.wait_for_function("document.querySelectorAll('.board.theme-dark .panel .phone').length >= 9")
    await assert_history_card_contract(page)
    chromium_version = browser.version
    for theme in themes:
      png_hashes[theme] = {}
      semantic_hashes[theme] = {}
      all_hotzones[theme] = {}
      all_semantics[theme] = {}
      for index, screen_id in enumerate(screens, start=1):
        phone = await page.wait_for_selector(f".board.theme-{theme} .panel:nth-of-type({index}) .phone")
        reference_path = generated_reference / theme / f"{screen_id}.png"
        reference_path.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(suffix=".png") as temp:
          await phone.screenshot(path=temp.name)
          with Image.open(temp.name).convert("RGB") as image:
            cropped = image.crop(INNER_CROP)
            if cropped.width != expected_width or cropped.height != expected_height:
              raise SystemExit(f"Generated PNG wrong size for {theme}/{screen_id}: {cropped.width}x{cropped.height}")
            cropped.save(reference_path)
        visual_sha = sha256(reference_path)
        semantics = await page.evaluate(
          EXTRACT_JS,
          {
            "theme": theme,
            "screenId": screen_id,
            "index": index,
            "visualSha": visual_sha,
            "sourceSha": source_sha,
            "expectedWidth": expected_width,
            "expectedHeight": expected_height,
          },
        )
        actual = set(semantics["bridge_action_ids"])
        expected = set(expected_action_ids(screen_id))
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        if missing or extra:
          message = []
          if missing:
            message.append(f"missing {missing}")
          if extra:
            message.append(f"extra {extra}")
          raise SystemExit(f"Generated semantics action set mismatch for {theme}/{screen_id}: {', '.join(message)}")
        png_hashes[theme][screen_id] = visual_sha
        all_hotzones[theme][screen_id] = semantics.pop("hotzones")
        all_semantics[theme][screen_id] = semantics
        semantic_hashes[theme][screen_id] = json_sha(semantics)
        write_json(generated_semantics / theme / f"{screen_id}.json", semantics)
        if artifact_reference_root is not None:
          artifact_png = artifact_reference_root / "reference" / theme / f"{screen_id}.png"
          artifact_png.parent.mkdir(parents=True, exist_ok=True)
          shutil.copy2(reference_path, artifact_png)
          write_json(artifact_reference_root / "semantics-reference" / theme / f"{screen_id}.json", semantics)
    await browser.close()

  hotzones = {
    "version": GENERATOR_VERSION,
    "screen_size": {"width": expected_width, "height": expected_height},
    "themes": themes,
    "screens": screens,
    "items": all_hotzones,
  }
  hotzones_sha = json_sha(hotzones)
  for theme in themes:
    for screen_id in screens:
      all_semantics[theme][screen_id]["hotzones_sha256"] = hotzones_sha
      all_semantics[theme][screen_id]["runtime_asset_sha256"] = None
      write_json(generated_semantics / theme / f"{screen_id}.json", all_semantics[theme][screen_id])
      semantic_hashes[theme][screen_id] = json_sha(all_semantics[theme][screen_id])
  write_json(output_root / "hotzones.json", hotzones)
  source_manifest = json.loads((WEB_ROOT / "manifest.json").read_text(encoding="utf-8"))
  provenance = {
    "version": GENERATOR_VERSION,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "source": "playwright-design-render",
    "designReference": str(REFERENCE_PATH.relative_to(ROOT)),
    "designReferenceSha256": design_sha,
    "sourceTreeSha256": source_sha,
    "generator": {
      "path": "Android/scripts/mobile_v4_validate_web_source.py",
      "version": GENERATOR_VERSION,
      "python": sys.executable,
      "platform": platform.platform(),
    },
    "playwright": playwright_metadata(),
    "chromium": {"version": chromium_version},
    "screenSize": {"width": expected_width, "height": expected_height},
    "themes": themes,
    "screens": screens,
    "visualPngSha256": png_hashes,
    "hotzonesSha256": hotzones_sha,
    "semanticSha256": semantic_hashes,
    "semantics": all_semantics,
    "sourceManifest": source_manifest,
  }
  write_json(output_root / "provenance.json", provenance)
  return provenance


def copy_runtime_assets(generated_root: Path, source_sha: str) -> None:
  if ASSET_ROOT.exists():
    shutil.rmtree(ASSET_ROOT)
  ASSET_ROOT.mkdir(parents=True)
  for file_name in ("index.html", "styles.css", "app.js", "schema.json"):
    shutil.copy2(SRC_ROOT / file_name, ASSET_ROOT / file_name)
  (ASSET_ROOT / "reference").mkdir()
  shutil.copy2(REFERENCE_PATH, ASSET_ROOT / "reference" / REFERENCE_PATH.name)
  shutil.copytree(REFERENCE_ASSETS_ROOT, ASSET_ROOT / "reference" / "assets")
  shutil.copytree(generated_root / "reference", ASSET_ROOT / "screens")
  shutil.copytree(generated_root / "semantics-reference", ASSET_ROOT / "semantics-reference")
  shutil.copy2(generated_root / "hotzones.json", ASSET_ROOT / "hotzones.json")
  shutil.copy2(generated_root / "provenance.json", ASSET_ROOT / "provenance.json")
  runtime_sha = tree_sha(ASSET_ROOT, exclude_self_referential=True)
  provenance = json.loads((ASSET_ROOT / "provenance.json").read_text(encoding="utf-8"))
  provenance["runtimeAssetSha256"] = runtime_sha
  provenance["assetTreeSha256"] = runtime_sha
  provenance["assetTreeHashExcludes"] = sorted(SELF_REFERENTIAL_FILES)
  write_json(ASSET_ROOT / "provenance.json", provenance)
  manifest = {
    "version": GENERATOR_VERSION,
    "sourceSha256": source_sha,
    "designReferenceSha256": sha256(REFERENCE_PATH),
    "runtimeAssetSha256": runtime_sha,
    "assetTreeSha256": runtime_sha,
    "assetTreeHashExcludes": sorted(SELF_REFERENTIAL_FILES),
    "hotzonesSha256": provenance["hotzonesSha256"],
    "entry": "index.html",
    "reference": f"reference/{REFERENCE_PATH.name}",
    "screens": "screens/{theme}/{screen_id}.png",
    "hotzones": "hotzones.json",
    "provenance": "provenance.json",
    "generatedBy": "Android/scripts/mobile_v4_validate_web_source.py --write",
  }
  write_json(ASSET_ROOT / "manifest.json", manifest)
  for semantic_path in (ASSET_ROOT / "semantics-reference").rglob("*.json"):
    data = json.loads(semantic_path.read_text(encoding="utf-8"))
    data["runtime_asset_sha256"] = runtime_sha
    write_json(semantic_path, data)


def assert_png_dimensions(root: Path) -> None:
  ensure_playwright_runtime()
  from PIL import Image

  _, _, expected_width, expected_height = screen_config()
  for png in sorted((root / "screens").rglob("*.png")):
    with Image.open(png) as image:
      if image.width != expected_width or image.height != expected_height:
        raise SystemExit(f"Packaged PNG has wrong dimensions: {png} {image.width}x{image.height}")


def assert_tree_equal(expected: Path, actual: Path, relative_files: list[str]) -> None:
  for relative in relative_files:
    expected_file = expected / relative
    actual_file = actual / relative
    if not expected_file.is_file():
      raise SystemExit(f"Internal generator error, missing expected file: {expected_file}")
    if not actual_file.is_file():
      raise SystemExit(f"Missing runtime asset: {actual_file}")
    if relative == "provenance.json":
      expected_payload = json.loads(expected_file.read_text(encoding="utf-8"))
      actual_payload = json.loads(actual_file.read_text(encoding="utf-8"))
      expected_payload.pop("generated_at", None)
      actual_payload.pop("generated_at", None)
      if expected_payload != actual_payload:
        raise SystemExit(f"Runtime asset is stale or hand-edited: {actual_file} differs from deterministic generator output")
    elif expected_file.read_bytes() != actual_file.read_bytes():
      raise SystemExit(f"Runtime asset is stale or hand-edited: {actual_file} differs from deterministic generator output")


def collect_generated_relatives(root: Path) -> list[str]:
  return sorted(path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file())


def validate_against_generated(temp_generated: Path) -> None:
  if not ASSET_ROOT.is_dir():
    raise SystemExit(f"Missing runtime asset root: {ASSET_ROOT}")
  packaged_reference = ASSET_ROOT / "reference" / REFERENCE_PATH.name
  if not packaged_reference.is_file() or packaged_reference.read_bytes() != REFERENCE_PATH.read_bytes():
    raise SystemExit(f"Packaged reference HTML drift: {packaged_reference}")
  for asset in sorted(REFERENCE_ASSETS_ROOT.rglob("*")):
    if not asset.is_file():
      continue
    packaged_asset = ASSET_ROOT / "reference" / "assets" / asset.relative_to(REFERENCE_ASSETS_ROOT)
    if not packaged_asset.is_file() or packaged_asset.read_bytes() != asset.read_bytes():
      raise SystemExit(f"Packaged reference asset drift: {packaged_asset}")
  relative_files = [
    "hotzones.json",
    "provenance.json",
    *[f"screens/{path.relative_to(temp_generated / 'reference').as_posix()}" for path in sorted((temp_generated / "reference").rglob("*.png"))],
    *[
      f"semantics-reference/{path.relative_to(temp_generated / 'semantics-reference').as_posix()}"
      for path in sorted((temp_generated / "semantics-reference").rglob("*.json"))
    ],
  ]
  assert_tree_equal(temp_generated, WEB_ROOT / "generated", collect_generated_relatives(temp_generated))
  for relative in relative_files:
    generated_file = temp_generated / relative.replace("screens/", "reference/", 1)
    if relative.startswith("semantics-reference/"):
      generated_file = temp_generated / relative
    elif relative in ("hotzones.json", "provenance.json"):
      generated_file = temp_generated / relative
    actual_file = ASSET_ROOT / relative
    if not actual_file.is_file():
      raise SystemExit(f"Missing packaged runtime asset: {actual_file}")
    if relative == "provenance.json":
      expected = json.loads(generated_file.read_text(encoding="utf-8"))
      actual = json.loads(actual_file.read_text(encoding="utf-8"))
      for volatile in ("generated_at", "runtimeAssetSha256", "assetTreeSha256", "assetTreeHashExcludes"):
        expected.pop(volatile, None)
        actual.pop(volatile, None)
      if expected != actual:
        raise SystemExit(f"Packaged provenance drift: {actual_file}")
    else:
      if relative.startswith("semantics-reference/"):
        expected = json.loads(generated_file.read_text(encoding="utf-8"))
        actual = json.loads(actual_file.read_text(encoding="utf-8"))
        expected.pop("runtime_asset_sha256", None)
        actual.pop("runtime_asset_sha256", None)
        if expected != actual:
          raise SystemExit(f"Packaged runtime semantic drift: {actual_file}")
      elif generated_file.read_bytes() != actual_file.read_bytes():
        raise SystemExit(f"Packaged runtime asset drift: {actual_file}")
  manifest = json.loads((ASSET_ROOT / "manifest.json").read_text(encoding="utf-8"))
  expected_runtime_sha = tree_sha(ASSET_ROOT, exclude_self_referential=True)
  if manifest.get("runtimeAssetSha256") != expected_runtime_sha:
    raise SystemExit(f"Runtime asset SHA drift: {manifest.get('runtimeAssetSha256')} != {expected_runtime_sha}")
  provenance = json.loads((ASSET_ROOT / "provenance.json").read_text(encoding="utf-8"))
  if provenance.get("source") != "playwright-design-render":
    raise SystemExit("Packaged provenance source must be playwright-design-render")
  if provenance.get("assetTreeSha256") != expected_runtime_sha:
    raise SystemExit("Packaged provenance asset tree hash drift")
  assert_png_dimensions(ASSET_ROOT)


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument(
    "--design",
    type=Path,
    default=ROOT / ".codex" / "artifacts" / "mobile-design-reference" / "clipdock-mobile-complete-design-v4.html",
  )
  parser.add_argument("--write", action="store_true", help="Regenerate Android app assets from Android/ui-web/mobile-v4")
  parser.add_argument("--artifact-root", type=Path, default=ARTIFACT_ROOT)
  args = parser.parse_args()

  assert_required_files()
  assert_no_network_resources()
  if not args.design.is_file():
    raise SystemExit(f"Missing authoritative design snapshot: {args.design}")
  design_sha = sha256(args.design)
  reference_sha = sha256(REFERENCE_PATH)
  if design_sha != reference_sha:
    raise SystemExit(f"Reference SHA drift: {REFERENCE_PATH} {reference_sha} != design {design_sha}")
  design_asset = args.design.parent / "assets" / REFERENCE_IMAGE_ASSET.name
  if not design_asset.is_file():
    raise SystemExit(f"Missing authoritative design image asset: {design_asset}")
  if sha256(design_asset) != sha256(REFERENCE_IMAGE_ASSET):
    raise SystemExit(f"Reference image asset drift: {REFERENCE_IMAGE_ASSET} != design asset {design_asset}")
  source_sha = source_tree_sha()
  with tempfile.TemporaryDirectory(prefix="clipdock-mobile-v4-generated-") as temp_dir:
    temp_generated = Path(temp_dir)
    provenance = asyncio.run(render_generated_assets(temp_generated, artifact_reference_root=args.artifact_root if args.write else None))
    if args.write:
      if GENERATED_ROOT.exists():
        shutil.rmtree(GENERATED_ROOT)
      shutil.copytree(temp_generated, GENERATED_ROOT)
      copy_runtime_assets(GENERATED_ROOT, source_sha)
    validate_against_generated(temp_generated)
  result = {
    "status": "ok",
    "designSha256": design_sha,
    "sourceSha256": source_sha,
    "runtimeAssetSha256": tree_sha(ASSET_ROOT, exclude_self_referential=True),
    "hotzonesSha256": provenance["hotzonesSha256"],
    "assetRoot": str(ASSET_ROOT),
    "generatedRoot": str(GENERATED_ROOT),
  }
  print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
