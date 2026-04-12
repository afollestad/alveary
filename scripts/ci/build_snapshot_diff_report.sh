#!/usr/bin/env bash
set -euo pipefail

# Generates a self-contained HTML report comparing reference and CI-recorded
# snapshot images side-by-side with before/after/onion-skin views.
#
# Usage: build_snapshot_diff_report.sh --ref-dir <path> --ci-dir <path> --output <path>

ref_dir=""
ci_dir=""
output=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref-dir)  ref_dir="$2"; shift 2 ;;
    --ci-dir)   ci_dir="$2"; shift 2 ;;
    --output)   output="$2"; shift 2 ;;
    *)          echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$ref_dir" ] || [ -z "$ci_dir" ] || [ -z "$output" ]; then
  echo "Usage: build_snapshot_diff_report.sh --ref-dir <path> --ci-dir <path> --output <path>" >&2
  exit 1
fi

entries=""
for ci_img in $(find "$ci_dir" -name '*.png' | sort); do
  rel="${ci_img#$ci_dir/}"
  ref_img="$ref_dir/$rel"
  [ -f "$ref_img" ] || continue

  ref_b64=$(base64 < "$ref_img")
  ci_b64=$(base64 < "$ci_img")
  name=$(basename "$rel" .png)

  entries="$entries
<div class=\"entry\">
  <h2>$name</h2>
  <div class=\"tabs\">
    <button class=\"tab active\" onclick=\"showTab(this,'side')\">Side by Side</button>
    <button class=\"tab\" onclick=\"showTab(this,'onion')\">Onion Skin</button>
  </div>
  <div class=\"panel side active\">
    <div class=\"col\"><h3>Reference (local)</h3><img src=\"data:image/png;base64,$ref_b64\"></div>
    <div class=\"col\"><h3>CI</h3><img src=\"data:image/png;base64,$ci_b64\"></div>
  </div>
  <div class=\"panel onion\">
    <div class=\"onion-wrap\">
      <img class=\"onion-base\" src=\"data:image/png;base64,$ref_b64\">
      <img class=\"onion-overlay\" src=\"data:image/png;base64,$ci_b64\">
      <input type=\"range\" min=\"0\" max=\"100\" value=\"50\" class=\"onion-slider\" oninput=\"this.previousElementSibling.style.opacity=this.value/100\">
    </div>
  </div>
</div>"
done

if [ -z "$entries" ]; then
  echo "No differing snapshots to report."
  exit 0
fi

mkdir -p "$(dirname "$output")"

cat > "$output" <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Snapshot Diff Report</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; background: #0d1117; color: #e6edf3; padding: 24px; }
  h1 { margin-bottom: 24px; font-size: 24px; }
  .entry { background: #161b22; border: 1px solid #30363d; border-radius: 8px; margin-bottom: 24px; padding: 16px; }
  .entry h2 { font-size: 16px; font-family: ui-monospace, monospace; margin-bottom: 12px; color: #7ee787; }
  .tabs { display: flex; gap: 8px; margin-bottom: 12px; }
  .tab { background: #21262d; border: 1px solid #30363d; border-radius: 6px; color: #8b949e; padding: 6px 14px; cursor: pointer; font-size: 13px; }
  .tab.active { background: #30363d; color: #e6edf3; }
  .panel { display: none; }
  .panel.active { display: flex; }
  .panel.side { gap: 16px; }
  .col { flex: 1; min-width: 0; }
  .col h3 { font-size: 13px; color: #8b949e; margin-bottom: 8px; }
  .col img { width: 100%; border: 1px solid #30363d; border-radius: 4px; }
  .panel.onion { justify-content: center; }
  .onion-wrap { position: relative; display: inline-block; }
  .onion-base { display: block; max-width: 100%; border: 1px solid #30363d; border-radius: 4px; }
  .onion-overlay { position: absolute; top: 0; left: 0; width: 100%; height: 100%; opacity: 0.5; border-radius: 4px; }
  .onion-slider { width: 100%; margin-top: 8px; }
</style>
</head>
<body>
<h1>Snapshot Diff Report</h1>
$entries
<script>
function showTab(btn, mode) {
  const entry = btn.closest('.entry');
  entry.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
  entry.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  btn.classList.add('active');
  entry.querySelector('.panel.' + mode).classList.add('active');
}
</script>
</body>
</html>
HTMLEOF

echo "Snapshot diff report written to $output"
