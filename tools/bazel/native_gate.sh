#!/usr/bin/env bash
set -euo pipefail

# swift-tui-swiftui native gate: build + run the SwiftUIHost test suite with
# SwiftPM. SwiftUIHost is an Apple-only module (it imports SwiftUI/AppKit/UIKit),
# so the gate runs on macOS and resolves the `swift-tui` runtime from its public
# tagged release. Matches the org toolchain convention (swiftly-managed Swift).

script_source="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
  script_path="$(realpath "$script_source")"
else
  script_path="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$script_source")"
fi

repo_root="$(git -C "$(dirname "$script_path")" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  repo_root="$(cd "$(dirname "$script_path")/../.." && pwd)"
fi

cd "$repo_root"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'swift-tui-swiftui native gate: SwiftUIHost is Apple-only; skipping on %s\n' "$(uname -s)"
  exit 0
fi

if command -v swiftly >/dev/null 2>&1; then
  exec swiftly run swift test
fi

exec swift test
