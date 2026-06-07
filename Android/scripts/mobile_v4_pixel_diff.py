#!/usr/bin/env python3
"""Compare Android V4 screenshots against HTML references."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANDROID_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ANDROID_ROOT / "qa" / "mobile-v4-pixel-config.json"
MASKS_PATH = ANDROID_ROOT / "qa" / "mobile-v4-pixel-masks.json"
DEFAULT_ROOT = ROOT / ".codex" / "artifacts" / "android-mobile-v4-pixel"
GENERATED_ROOT = ANDROID_ROOT / "ui-web" / "mobile-v4" / "generated" / "reference"


def load_image(path: Path):
  try:
    from PIL import Image
    import numpy as np
  except ModuleNotFoundError as exc:
    raise SystemExit("Missing dependency: install Android/qa/mobile-v4-pixel-requirements.txt.") from exc
  if not path.is_file():
    raise SystemExit(f"Missing screenshot: {path}")
  return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def sha256(path: Path) -> str:
  digest = hashlib.sha256()
  with path.open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
      digest.update(chunk)
  return digest.hexdigest()


def load_json(path: Path) -> dict:
  if not path.is_file():
    raise SystemExit(f"Missing JSON artifact: {path}")
  return json.loads(path.read_text(encoding="utf-8"))


def mask_for(screen_id: str, theme: str, shape: tuple[int, int]):
  import numpy as np

  mask = np.ones(shape, dtype=bool)
  if not MASKS_PATH.is_file():
    return mask
  data = json.loads(MASKS_PATH.read_text())
  for entry in data.get("masks", []):
    screens = entry.get("screens", [])
    themes = entry.get("themes", [])
    if "*" not in screens and screen_id not in screens:
      continue
    if "*" not in themes and theme not in themes:
      continue
    rect = entry["rect"]
    x = max(0, int(rect["x"]))
    y = max(0, int(rect["y"]))
    width = max(0, int(rect["width"]))
    height = max(0, int(rect["height"]))
    mask[y : y + height, x : x + width] = False
  return mask


def save_diff(path: Path, diff):
  from PIL import Image
  import numpy as np

  path.parent.mkdir(parents=True, exist_ok=True)
  heat = np.clip(diff * 8.0, 0.0, 1.0)
  rgb = np.zeros((*heat.shape, 3), dtype=np.uint8)
  rgb[..., 0] = (heat * 255).astype(np.uint8)
  rgb[..., 1] = ((1.0 - heat) * 60).astype(np.uint8)
  Image.fromarray(rgb, mode="RGB").save(path)


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
  args = parser.parse_args()

  try:
    import numpy as np
    from skimage.metrics import structural_similarity
  except ModuleNotFoundError as exc:
    raise SystemExit("Missing dependency: install Android/qa/mobile-v4-pixel-requirements.txt.") from exc

  config = json.loads(CONFIG_PATH.read_text())
  metadata_path = args.root / "android-metadata.json"
  android_metadata = json.loads(metadata_path.read_text()) if metadata_path.is_file() else {}
  if "android WebView reference mode" in android_metadata.get("capture_source", ""):
    raise SystemExit("Rejecting android-vs-android self-comparison: Android capture metadata declares reference mode")
  if "production WebView" not in android_metadata.get("capture_source", ""):
    raise SystemExit("Rejecting Android capture without installed production WebView provenance")
  asset_hashes = load_json(args.root / "apk" / "asset-hashes.json")
  installed_provenance = load_json(args.root / "apk" / "assets" / "clipdock-mobile-v4" / "provenance.json")
  if installed_provenance.get("source") != "playwright-design-render":
    raise SystemExit("Rejecting installed APK assets without Playwright generator provenance")
  android_screens = {
    (entry.get("theme"), entry.get("screen_id")): entry
    for entry in android_metadata.get("screens", [])
  }
  thresholds = config["thresholds"]
  results = []
  for theme in config["themes"]:
    for screen_id in config["screens"]:
      reference_path = args.root / "reference" / theme / f"{screen_id}.png"
      android_path = args.root / "android" / theme / f"{screen_id}.png"
      generated_path = GENERATED_ROOT / theme / f"{screen_id}.png"
      runtime_semantics_path = args.root / "semantics" / theme / f"{screen_id}.json"
      reference_semantics_path = args.root / "semantics-reference" / theme / f"{screen_id}.json"
      if reference_path.resolve() == android_path.resolve():
        raise SystemExit(f"Rejecting self-comparison for {theme}/{screen_id}: reference and android paths are identical")
      if "/android/" in reference_path.as_posix():
        raise SystemExit(f"Rejecting android-vs-android self-comparison for {theme}/{screen_id}: {reference_path}")
      reference_sha = sha256(reference_path)
      generated_sha = sha256(generated_path)
      android_sha = sha256(android_path)
      runtime_semantics = load_json(runtime_semantics_path)
      reference_semantics = load_json(reference_semantics_path)
      installed_png_relative = f"clipdock-mobile-v4/screens/{theme}/{screen_id}.png"
      installed_png_sha = asset_hashes.get(installed_png_relative)
      if not installed_png_sha:
        raise SystemExit(f"Missing installed APK PNG hash for {theme}/{screen_id}")
      android_screen_metadata = android_screens.get((theme, screen_id), {})
      binding_checks = {
        "playwright_reference_sha_equals_generated_png_sha": reference_sha == generated_sha,
        "installed_apk_png_sha_equals_generated_png_sha": installed_png_sha == generated_sha,
        "runtime_dom_screen_id_matches": runtime_semantics.get("screen_id") == screen_id,
        "runtime_dom_theme_matches": runtime_semantics.get("theme") == theme,
        "runtime_dom_visual_png_sha256_equals_installed_apk_png_sha": runtime_semantics.get("visual_png_sha256") == installed_png_sha,
        "runtime_dom_hotzones_sha256_equals_installed_apk_hotzones_sha": runtime_semantics.get("hotzones_sha256") == installed_provenance.get("hotzonesSha256"),
        "android_screenshot_state_confirmed_before_capture": android_screen_metadata.get("state_confirmed_before_capture") is True,
        "runtime_semantics_fallback_false": runtime_semantics.get("fallback") is False,
        "reference_semantics_fallback_false": reference_semantics.get("fallback") is False,
        "semantic_action_ids_match": sorted(runtime_semantics.get("bridge_action_ids", [])) == sorted(reference_semantics.get("bridge_action_ids", [])),
        "semantic_route_matches": runtime_semantics.get("route") == reference_semantics.get("route"),
        "semantic_active_sheet_matches": runtime_semantics.get("active_sheet") == reference_semantics.get("active_sheet"),
      }
      binding_failures = [name for name, passed in binding_checks.items() if not passed]
      reference = load_image(reference_path)
      android = load_image(android_path)
      reference_shape = list(reference.shape)
      android_shape = list(android.shape)
      failures = []
      if reference.shape != android.shape:
        failures.append(f"shape mismatch reference={reference.shape} android={android.shape}")
        min_h = min(reference.shape[0], android.shape[0])
        min_w = min(reference.shape[1], android.shape[1])
        reference = reference[:min_h, :min_w]
        android = android[:min_h, :min_w]
      compared_shape = list(reference.shape)
      mask = mask_for(screen_id, theme, reference.shape[:2])
      diff = np.abs(reference - android).mean(axis=2)
      masked_diff = diff[mask]
      rmse = math.sqrt(float(np.mean((reference[mask] - android[mask]) ** 2))) if masked_diff.size else 0.0
      changed_ratio = float(np.mean(masked_diff > (8 / 255))) if masked_diff.size else 0.0
      ssim = float(structural_similarity(reference, android, channel_axis=2, data_range=1.0))
      if ssim < thresholds["ssim_min"]:
        failures.append(f"ssim {ssim:.6f} < {thresholds['ssim_min']}")
      if rmse > thresholds["rmse_max"]:
        failures.append(f"rmse {rmse:.6f} > {thresholds['rmse_max']}")
      if changed_ratio > thresholds["changed_ratio_max"]:
        failures.append(f"changed_ratio {changed_ratio:.6f} > {thresholds['changed_ratio_max']}")
      failures.extend(f"binding failed: {name}" for name in binding_failures)
      diff_path = args.root / "diff" / theme / f"{screen_id}.png"
      save_diff(diff_path, diff)
      results.append(
        {
          "screen_id": screen_id,
          "theme": theme,
          "reference": str(reference_path),
          "android": str(android_path),
          "diff": str(diff_path),
          "mask": str(MASKS_PATH),
          "reference_png_sha256": reference_sha,
          "generated_png_sha256": generated_sha,
          "android_screenshot_sha256": android_sha,
          "installed_apk_png_sha256": installed_png_sha,
          "runtime_dom_visual_png_sha256": runtime_semantics.get("visual_png_sha256"),
          "runtime_dom_hotzones_sha256": runtime_semantics.get("hotzones_sha256"),
          "binding_checks": binding_checks,
          "reference_semantics": str(reference_semantics_path),
          "runtime_semantics": str(runtime_semantics_path),
          "reference_shape": reference_shape,
          "android_shape": android_shape,
          "compared_shape": compared_shape,
          "ssim": ssim,
          "rmse": rmse,
          "changed_ratio": changed_ratio,
          "passed": not failures,
          "failures": failures,
        }
      )

  summary = {
    "total": len(results),
    "passed": sum(1 for result in results if result["passed"]),
    "failed": sum(1 for result in results if not result["passed"]),
  }
  report = {
    "version": 1,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "config": config,
    "android_metadata": android_metadata,
    "reproducibility": {
      "generated_root": str(GENERATED_ROOT),
      "apk_sha256": android_metadata.get("apk", {}).get("sha256"),
      "device_serial": android_metadata.get("device_serial"),
      "webview_provider": android_metadata.get("webview_provider"),
      "installed_asset_hashes": str(args.root / "apk" / "asset-hashes.json"),
      "installed_provenance": str(args.root / "apk" / "assets" / "clipdock-mobile-v4" / "provenance.json"),
      "generator_version": installed_provenance.get("generator", {}).get("version"),
      "playwright": installed_provenance.get("playwright"),
      "chromium": installed_provenance.get("chromium"),
      "self_comparison_rejected": True,
    },
    "summary": summary,
    "results": results,
  }
  args.root.mkdir(parents=True, exist_ok=True)
  (args.root / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
  lines = [
    "# Android Mobile V4 Pixel QA Report",
    "",
    f"Generated: {report['generated_at']}",
    f"Summary: {summary['passed']}/{summary['total']} passed",
    "",
    "| Theme | Screen | SSIM | RMSE | Changed | Result |",
    "| --- | --- | ---: | ---: | ---: | --- |",
  ]
  for result in results:
    status = "PASS" if result["passed"] else "FAIL: " + "; ".join(result["failures"])
    if result["reference_shape"] != result["android_shape"]:
      status += f" (reference_shape={result['reference_shape']} android_shape={result['android_shape']})"
    lines.append(
      f"| {result['theme']} | {result['screen_id']} | {result['ssim']:.6f} | "
      f"{result['rmse']:.6f} | {result['changed_ratio']:.6f} | {status} |"
    )
  (args.root / "report.md").write_text("\n".join(lines) + "\n")
  print(f"Wrote {args.root / 'report.json'}")
  return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
  raise SystemExit(main())
