#!/usr/bin/env python3
"""Capture Android V4 pixel QA screens from an adb target."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import html
import re
import shutil
import subprocess
import time
import zipfile
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[2]
ANDROID_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ANDROID_ROOT / "qa" / "mobile-v4-pixel-config.json"
DEFAULT_OUTPUT = ROOT / ".codex" / "artifacts" / "android-mobile-v4-pixel"
DEFAULT_ADB = Path.home() / "Library" / "Android" / "sdk" / "platform-tools" / "adb"
ACTIVITY = "com.apkdv.clipdock/.qa.MobileV4PixelQaActivity"
UI_TREE_DEVICE_PATH = "/data/local/tmp/mobile-v4-window.xml"
SEMANTICS_CACHE_PATH = "cache/mobile-v4-semantics"
SCREEN_CACHE_PATH = "cache/mobile-v4-screens"
APK_REMOTE_DIR = "/data/local/tmp"


def selected_nav_for(screen_id: str) -> str | None:
  if screen_id in ("devices",):
    return "设备"
  if screen_id in ("files",):
    return "文件"
  if screen_id in ("settings", "keep_alive", "floating_ball"):
    return "设置"
  if screen_id in ("item_detail_text", "remote_asset_sheet", "delete_confirm"):
    return None
  return "历史"


def expected_tags_for(screen_id: str) -> list[str]:
  tags = [
    "history-card-qa-ready-text",
    "history-card-qa-remote-image",
    "history-card-qa-link",
    "history-card-qa-ready-file",
    "history-card-qa-color",
  ]
  if screen_id in ("item_detail_text", "remote_asset_sheet", "delete_confirm"):
    tags += [
      "item-detail-screen",
      "item-detail-primary-action",
      "item-detail-trash-action",
    ]
  if screen_id == "remote_asset_sheet":
    tags += [
      "remote-retrieval-sheet",
      "remote-download-and-copy",
      "remote-download-to-cache",
      "remote-copy-thumbnail",
    ]
  if screen_id == "delete_confirm":
    tags += [
      "delete-confirm-sheet",
      "delete-remove-local-cache",
      "delete-sync-record",
      "delete-cancel",
    ]
  return sorted(set(tags))


def primary_actions_for(screen_id: str) -> list[str]:
  if screen_id == "remote_asset_sheet":
    return ["下载并复制", "仅下载到本机缓存", "复制缩略图"]
  if screen_id == "delete_confirm":
    return ["仅移除本机缓存", "删除同步记录", "取消"]
  if screen_id == "item_detail_text":
    return ["复制"]
  return []


def enabled_states_for(screen_id: str) -> dict[str, bool]:
  if screen_id == "remote_asset_sheet":
    return {
      "下载并复制": True,
      "仅下载到本机缓存": True,
      "复制缩略图": True,
    }
  if screen_id == "delete_confirm":
    return {
      "仅移除本机缓存": False,
      "删除同步记录": True,
      "取消": True,
    }
  if screen_id == "item_detail_text":
    return {"复制": True}
  return {}


def parse_bounds(raw: str) -> dict[str, int] | None:
  match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", raw or "")
  if not match:
    return None
  left, top, right, bottom = (int(group) for group in match.groups())
  return {
    "x": left,
    "y": top,
    "width": max(0, right - left),
    "height": max(0, bottom - top),
  }


def semantic_nodes_from_xml(ui_tree: Path) -> list[dict[str, object]]:
  if not ui_tree.is_file():
    return []
  text = ui_tree.read_text(errors="replace")
  if text.lstrip().startswith("<!--"):
    return []
  try:
    root = ElementTree.fromstring(text)
  except ElementTree.ParseError:
    return []
  nodes: list[dict[str, object]] = []
  for node in root.iter("node"):
    node_text = node.attrib.get("text", "")
    content_desc = node.attrib.get("content-desc", "")
    resource_id = node.attrib.get("resource-id", "")
    visible_text = node_text or content_desc
    bounds = parse_bounds(node.attrib.get("bounds", ""))
    if not visible_text and not resource_id:
      continue
    entry: dict[str, object] = {
      "text": visible_text,
      "resource_id": resource_id,
      "content_description": content_desc,
      "enabled": node.attrib.get("enabled") == "true",
      "clickable": node.attrib.get("clickable") == "true",
    }
    if bounds is not None:
      entry["bounds"] = bounds
    nodes.append(entry)
  return nodes


def write_semantics_fallback(
  output_root: Path,
  theme: str,
  screen_id: str,
  ui_tree: Path,
  *,
  expected_width: int,
  expected_height: int,
) -> None:
  nodes = semantic_nodes_from_xml(ui_tree)
  visible_texts = []
  key_bounds: dict[str, object] = {
    "screen": {"x": 0, "y": 0, "width": expected_width, "height": expected_height}
  }
  seen_texts = set()
  for node in nodes:
    node_text = str(node.get("text") or "")
    if node_text and node_text not in seen_texts:
      visible_texts.append(node_text)
      seen_texts.add(node_text)
      if "bounds" in node:
        key_bounds[node_text] = node["bounds"]
  semantics = {
    "version": 1,
    "screen_id": screen_id,
    "theme": theme,
    "source": "uiautomator supplement fallback; DOM semantic export unavailable",
    "route": screen_id,
    "active_sheet": "remote_retrieval" if screen_id == "remote_asset_sheet" else "delete_confirm" if screen_id == "delete_confirm" else None,
    "selected_nav": selected_nav_for(screen_id),
    "visible_texts": visible_texts,
    "bridge_action_ids": expected_tags_for(screen_id),
    "enabled_states": enabled_states_for(screen_id),
    "focus_order": visible_texts,
    "aria_labels": [],
    "touch_targets_px": {},
    "key_bounds_px": key_bounds,
    "source_sha256": None,
    "runtime_asset_sha256": None,
    "ui_tree": str(ui_tree),
    "nodes": nodes,
  }
  path = output_root / "semantics" / theme / f"{screen_id}.json"
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(semantics, ensure_ascii=False, indent=2) + "\n")


def pull_dom_semantics(
  adb: str,
  device: str | None,
  package: str,
  output_root: Path,
  theme: str,
  screen_id: str,
) -> dict[str, object]:
  remote = f"{SEMANTICS_CACHE_PATH}/{theme}/{screen_id}.json"
  try:
    text = run(adb_args(adb, device, "shell", "run-as", package, "cat", remote))
    data = json.loads(text)
  except (SystemExit, json.JSONDecodeError) as exc:
    raise SystemExit(f"Missing production DOM semantic export for {theme}/{screen_id}: {exc}") from exc
  required = [
    "screen_id",
    "theme",
    "route",
    "active_sheet",
    "selected_nav",
    "visible_texts",
    "bridge_action_ids",
    "enabled_states",
    "focus_order",
    "aria_labels",
    "touch_targets_px",
    "key_bounds_px",
    "source_sha256",
    "runtime_asset_sha256",
    "visual_png_sha256",
    "hotzones_sha256",
    "runtime_dom_source",
    "semantic_source",
    "fallback",
  ]
  missing = [key for key in required if key not in data]
  if missing:
    raise SystemExit(f"DOM semantic export missing fields for {theme}/{screen_id}: {missing}")
  if data.get("fallback") is not False:
    raise SystemExit(f"DOM semantic export fallback is not allowed for {theme}/{screen_id}")
  if data.get("screen_id") != screen_id or data.get("theme") != theme:
    raise SystemExit(f"DOM semantic export state mismatch for {theme}/{screen_id}: {data.get('theme')}/{data.get('screen_id')}")
  path = output_root / "semantics" / theme / f"{screen_id}.json"
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
  return data


def pull_webview_png(
  adb: str,
  device: str | None,
  package: str,
  output: Path,
  theme: str,
  screen_id: str,
  *,
  expected_width: int,
  expected_height: int,
) -> bool:
  remote = f"{SCREEN_CACHE_PATH}/{theme}/{screen_id}.png"
  try:
    png = run_bytes(adb_args(adb, device, "exec-out", "run-as", package, "cat", remote))
  except SystemExit:
    return False
  try:
    width, height = decode_png_size(png)
  except Exception:
    return False
  if width != expected_width or height != expected_height or is_blank_screenshot(png):
    return False
  output.parent.mkdir(parents=True, exist_ok=True)
  output.write_bytes(png)
  return True


def run(args: list[str], *, output: Path | None = None) -> str:
  try:
    completed = subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  except FileNotFoundError as exc:
    raise SystemExit(f"Missing executable: {args[0]}") from exc
  except subprocess.CalledProcessError as exc:
    stderr = exc.stderr.decode(errors="replace")
    stdout = exc.stdout.decode(errors="replace")
    raise SystemExit(f"Command failed: {' '.join(args)}\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}") from exc
  if output is not None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(completed.stdout)
  return completed.stdout.decode(errors="replace")


def run_bytes(args: list[str]) -> bytes:
  try:
    completed = subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  except FileNotFoundError as exc:
    raise SystemExit(f"Missing executable: {args[0]}") from exc
  except subprocess.CalledProcessError as exc:
    stderr = exc.stderr.decode(errors="replace")
    stdout = exc.stdout.decode(errors="replace")
    raise SystemExit(f"Command failed: {' '.join(args)}\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}") from exc
  return completed.stdout


def run_optional(args: list[str]) -> str:
  try:
    return run(args)
  except SystemExit as exc:
    return f"unavailable: {exc}"


def sha256_bytes(data: bytes) -> str:
  return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
  digest = hashlib.sha256()
  with path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
      digest.update(chunk)
  return digest.hexdigest()


def extract_installed_assets(adb: str, device: str | None, package: str, output_root: Path) -> dict[str, object]:
  package_line = run(adb_args(adb, device, "shell", "pm", "path", package)).strip().splitlines()[0]
  remote_apk = package_line.removeprefix("package:")
  apk_dir = output_root / "apk"
  apk_dir.mkdir(parents=True, exist_ok=True)
  local_apk = apk_dir / "installed.apk"
  run(adb_args(adb, device, "pull", remote_apk, str(local_apk)))
  assets_root = apk_dir / "assets"
  if assets_root.exists():
    shutil.rmtree(assets_root)
  asset_hashes: dict[str, str] = {}
  with zipfile.ZipFile(local_apk) as archive:
    for name in sorted(archive.namelist()):
      prefix = "assets/clipdock-mobile-v4/"
      if not name.startswith(prefix) or name.endswith("/"):
        continue
      data = archive.read(name)
      relative = name[len("assets/") :]
      target = assets_root / relative
      target.parent.mkdir(parents=True, exist_ok=True)
      target.write_bytes(data)
      asset_hashes[relative] = sha256_bytes(data)
  if not asset_hashes:
    raise SystemExit(f"No clipdock-mobile-v4 assets found in installed APK: {local_apk}")
  package_info = run_optional(adb_args(adb, device, "shell", "dumpsys", "package", package))
  metadata = {
    "apk_sha256": sha256(local_apk),
    "apk_path": str(local_apk),
    "remote_apk_path": remote_apk,
    "package": package,
    "package_info": package_info,
    "asset_hashes": asset_hashes,
    "asset_root": str(assets_root / "clipdock-mobile-v4"),
  }
  (apk_dir / "package.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
  (apk_dir / "asset-hashes.json").write_text(json.dumps(asset_hashes, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
  return metadata


def adb_args(adb: str, device: str | None, *parts: str) -> list[str]:
  result = [adb]
  if device:
    result += ["-s", device]
  result += list(parts)
  return result


def current_focus(adb: str, device: str | None) -> str:
  window_state = run(adb_args(adb, device, "shell", "dumpsys", "window", "windows"))
  for marker in ("mCurrentFocus=", "mFocusedApp="):
    for line in window_state.splitlines():
      if marker in line:
        return line.strip()
  activity_state = run(adb_args(adb, device, "shell", "dumpsys", "activity", "activities"))
  for marker in ("topResumedActivity=", "ResumedActivity:", "Resumed:"):
    for line in activity_state.splitlines():
      if marker in line:
        return line.strip()
  return ""


def wait_for_activity(adb: str, device: str | None, *, timeout_seconds: float = 30.0) -> None:
  deadline = time.monotonic() + timeout_seconds
  last_focus = ""
  while time.monotonic() < deadline:
    last_focus = current_focus(adb, device)
    if "MobileV4PixelQaActivity" in last_focus:
      return
    time.sleep(0.25)
  raise SystemExit(f"Timed out waiting for MobileV4PixelQaActivity focus. Last focus: {last_focus or '<none>'}")


def decode_png_size(png: bytes) -> tuple[int, int]:
  try:
    from PIL import Image
  except ModuleNotFoundError as exc:
    raise SystemExit("Missing dependency: install Android/qa/mobile-v4-pixel-requirements.txt.") from exc
  with Image.open(io.BytesIO(png)) as image:
    return image.width, image.height


def is_blank_screenshot(png: bytes) -> bool:
  try:
    from PIL import Image, ImageStat
  except ModuleNotFoundError as exc:
    raise SystemExit("Missing dependency: install Android/qa/mobile-v4-pixel-requirements.txt.") from exc
  with Image.open(io.BytesIO(png)).convert("RGB") as image:
    stat = ImageStat.Stat(image)
    return max(stat.stddev) < 2.0


def write_png_artifact(path: Path, png: bytes) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_bytes(png)


def capture_expected_screenshot(
  adb: str,
  device: str | None,
  path: Path,
  *,
  expected_width: int,
  expected_height: int,
  timeout_seconds: float = 6.0,
) -> None:
  deadline = time.monotonic() + timeout_seconds
  last_size: tuple[int, int] | None = None
  last_png: bytes | None = None
  last_was_blank = False
  while time.monotonic() < deadline:
    png = run_bytes(adb_args(adb, device, "exec-out", "screencap", "-p"))
    width, height = decode_png_size(png)
    blank = is_blank_screenshot(png)
    last_size = (width, height)
    last_png = png
    last_was_blank = blank
    if width == expected_width and height == expected_height and not blank:
      write_png_artifact(path, png)
      return
    time.sleep(0.25)
  if last_png is None:
    raise SystemExit(f"Screenshot capture failed for {path}: no PNG data returned")
  if last_size != (expected_width, expected_height):
    bad_path = path.with_name(path.stem + ".wrong-size.png")
    write_png_artifact(bad_path, last_png)
    raise SystemExit(
      f"Screenshot dimension mismatch for {path}: last={last_size}, "
      f"expected={expected_width}x{expected_height}. Last wrong-size screenshot: {bad_path}"
    )
  if last_was_blank:
    blank_path = path.with_name(path.stem + ".blank.png")
    write_png_artifact(blank_path, last_png)
    raise SystemExit(
      f"Screenshot blank raster for {path}: size={expected_width}x{expected_height}, "
      f"but image variance is below blank threshold. Last blank screenshot: {blank_path}"
    )
  unknown_path = path.with_name(path.stem + ".rejected.png")
  write_png_artifact(unknown_path, last_png)
  raise SystemExit(f"Screenshot rejected for {path}: last_size={last_size}. Last rejected screenshot: {unknown_path}")


def capture_ui_tree(adb: str, device: str | None, ui_tree: Path) -> None:
  ui_tree.parent.mkdir(parents=True, exist_ok=True)
  try:
    run(adb_args(adb, device, "shell", "rm", "-f", UI_TREE_DEVICE_PATH))
    run(adb_args(adb, device, "shell", "uiautomator", "dump", UI_TREE_DEVICE_PATH))
    run(adb_args(adb, device, "pull", UI_TREE_DEVICE_PATH, str(ui_tree)))
  except SystemExit as exc:
    message = str(exc)
    ui_tree.write_text(f"<!-- UI tree unavailable: {html.escape(message)} -->\n")
    print(f"Warning: UI tree unavailable for {ui_tree}: {message}")


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--adb", default=str(DEFAULT_ADB if DEFAULT_ADB.exists() else shutil.which("adb") or DEFAULT_ADB))
  parser.add_argument("--device", default=None)
  parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
  parser.add_argument("--package", default="com.apkdv.clipdock")
  args = parser.parse_args()

  if not Path(args.adb).exists() and shutil.which(args.adb) is None:
    raise SystemExit(f"adb not found: {args.adb}")
  if not CONFIG_PATH.is_file():
    raise SystemExit(f"Missing pixel config: {CONFIG_PATH}")

  config = json.loads(CONFIG_PATH.read_text())
  screens = config["screens"]
  themes = config["themes"]
  size = config["screen_size"]
  expected_width = int(size["width"])
  expected_height = int(size["height"])

  run(adb_args(args.adb, args.device, "shell", "wm", "size", f"{size['width']}x{size['height']}"))
  run(adb_args(args.adb, args.device, "shell", "wm", "density", str(size["density"])))
  run(adb_args(args.adb, args.device, "shell", "settings", "put", "system", "font_scale", "1.0"))
  run(adb_args(args.adb, args.device, "shell", "settings", "put", "secure", "immersive_mode_confirmations", "confirmed"))
  for scale in ("window_animation_scale", "transition_animation_scale", "animator_duration_scale"):
    run(adb_args(args.adb, args.device, "shell", "settings", "put", "global", scale, "0"))

  run(adb_args(args.adb, args.device, "shell", "am", "force-stop", args.package))
  installed_assets = extract_installed_assets(args.adb, args.device, args.package, args.output)
  installed_hotzones_sha = installed_assets["asset_hashes"].get("clipdock-mobile-v4/hotzones.json")
  metadata = {
    "capture_source": "production WebView route via MobileV4PixelQaActivity",
    "activity": ACTIVITY,
    "webview_update": run_optional(adb_args(args.adb, args.device, "shell", "dumpsys", "webviewupdate")),
    "api_level": run_optional(adb_args(args.adb, args.device, "shell", "getprop", "ro.build.version.sdk")).strip(),
    "webview_provider": run_optional(adb_args(args.adb, args.device, "shell", "cmd", "webviewupdate", "get-current-webview-package")).strip(),
    "device_serial": run_optional(adb_args(args.adb, args.device, "get-serialno")).strip(),
    "apk": {
      "sha256": installed_assets["apk_sha256"],
      "path": installed_assets["apk_path"],
      "remote_path": installed_assets["remote_apk_path"],
    },
    "installed_asset_hashes_path": str(args.output / "apk" / "asset-hashes.json"),
    "screens": [],
  }
  for theme in themes:
    run(adb_args(args.adb, args.device, "shell", "cmd", "uimode", "night", "yes" if theme == "dark" else "no"))
    for screen_id in screens:
      for attempt in range(1, 4):
        if attempt > 1:
          print(f"Retrying launch for {theme}/{screen_id}, attempt {attempt}/3")
          run(adb_args(args.adb, args.device, "shell", "am", "force-stop", args.package))
          time.sleep(1.0)
        launch_output = run(
          adb_args(
            args.adb,
            args.device,
            "shell",
            "am",
            "start",
            "-S",
            "-W",
            "-n",
            ACTIVITY,
            "--es",
            "screen_id",
            screen_id,
            "--es",
            "theme",
            theme,
            "--ez",
            "include_reference_status",
            "true",
          )
        )
        if ".qa.MobileV4PixelQaActivity" not in launch_output:
          if attempt == 3:
            raise SystemExit(f"Unexpected activity launch output for {theme}/{screen_id}:\n{launch_output}")
          continue
        try:
          wait_for_activity(args.adb, args.device)
          break
        except SystemExit:
          if attempt == 3:
            raise
      else:
        raise SystemExit(f"Could not launch MobileV4PixelQaActivity for {theme}/{screen_id}")
      screenshot = args.output / "android" / theme / f"{screen_id}.png"
      ui_tree = args.output / "ui-tree" / theme / f"{screen_id}.xml"
      capture_ui_tree(args.adb, args.device, ui_tree)
      time.sleep(0.8)
      semantics = pull_dom_semantics(args.adb, args.device, args.package, args.output, theme, screen_id)
      installed_png_relative = f"clipdock-mobile-v4/screens/{theme}/{screen_id}.png"
      installed_png_sha = installed_assets["asset_hashes"].get(installed_png_relative)
      if not installed_png_sha:
        raise SystemExit(f"Installed APK missing runtime PNG: {installed_png_relative}")
      if semantics.get("visual_png_sha256") != installed_png_sha:
        raise SystemExit(
          f"Runtime DOM visual hash mismatch for {theme}/{screen_id}: "
          f"{semantics.get('visual_png_sha256')} != installed {installed_png_sha}"
        )
      if semantics.get("hotzones_sha256") != installed_hotzones_sha and semantics.get("hotzones_sha256") != json.loads((args.output / "apk" / "assets" / "clipdock-mobile-v4" / "provenance.json").read_text()).get("hotzonesSha256"):
        raise SystemExit(f"Runtime DOM hotzones hash mismatch for {theme}/{screen_id}: {semantics.get('hotzones_sha256')}")
      if not pull_webview_png(
        args.adb,
        args.device,
        args.package,
        screenshot,
        theme,
        screen_id,
        expected_width=expected_width,
        expected_height=expected_height,
      ):
        capture_expected_screenshot(
          args.adb,
          args.device,
          screenshot,
          expected_width=expected_width,
          expected_height=expected_height,
        )
      metadata["screens"].append(
        {
          "theme": theme,
          "screen_id": screen_id,
          "url": f"appassets://clipdock-mobile-v4/{screen_id}",
          "state_confirmed_before_capture": True,
          "runtime_dom_visual_png_sha256": semantics.get("visual_png_sha256"),
          "runtime_dom_hotzones_sha256": semantics.get("hotzones_sha256"),
          "installed_apk_png_sha256": installed_png_sha,
        }
      )
      print(f"Captured {theme}/{screen_id}")
  args.output.mkdir(parents=True, exist_ok=True)
  (args.output / "android-metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
