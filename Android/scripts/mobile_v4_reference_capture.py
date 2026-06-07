#!/usr/bin/env python3
"""Capture canonical V4 HTML reference screens through the Rev5 generator."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANDROID_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HTML = ANDROID_ROOT / "ui-web" / "mobile-v4" / "reference" / "clipdock-mobile-complete-design-v4.html"
DEFAULT_OUTPUT = ROOT / ".codex" / "artifacts" / "android-mobile-v4-pixel" / "reference"
GENERATOR = ANDROID_ROOT / "scripts" / "mobile_v4_validate_web_source.py"


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--html", type=Path, default=DEFAULT_HTML)
  parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
  args = parser.parse_args()

  if args.html.resolve() != DEFAULT_HTML.resolve():
    raise SystemExit("Revision 5 reference capture must use Android-owned authoritative HTML")
  artifact_root = args.output.parent
  command = [
    sys.executable,
    str(GENERATOR),
    "--design",
    str(ROOT / ".codex" / "artifacts" / "mobile-design-reference" / "clipdock-mobile-complete-design-v4.html"),
    "--write",
    "--artifact-root",
    str(artifact_root),
  ]
  completed = subprocess.run(command, cwd=ROOT, check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  if completed.stderr:
    print(completed.stderr, file=sys.stderr)
  print(completed.stdout, end="")
  print(f"Captured Rev5 Playwright reference screens into {args.output}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
