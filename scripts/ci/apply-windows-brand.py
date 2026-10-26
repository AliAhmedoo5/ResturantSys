"""Bundle the approved PNG mark as a multi-resolution Windows icon in CI."""

import os
from pathlib import Path
import re

from PIL import Image


if os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Windows app branding artifacts must be generated in GitHub Actions.")

root = Path(__file__).resolve().parents[2]
icon_path = root / "windows/runner/resources/app_icon.ico"
sizes = [(side, side) for side in (16, 24, 32, 48, 64, 128, 256)]
with Image.open(root / "assets/brand/crunch-cartel-icon.png") as source:
    source.convert("RGBA").save(icon_path, format="ICO", sizes=sizes)
with Image.open(icon_path) as icon:
    if not set(sizes).issubset(icon.info["sizes"]):
        raise RuntimeError("The Windows icon is missing required resolutions.")

runner_path = root / "windows/runner/main.cpp"
runner = runner_path.read_text(encoding="utf-8")
runner, count = re.subn(r'window\.Create\(L"[^"]*"',
                      'window.Create(L"Crunch Cartel POS"', runner)
if count != 1:
    raise RuntimeError("Could not locate the generated Windows window title.")
runner_path.write_text(runner, encoding="utf-8")

resource_path = root / "windows/runner/Runner.rc"
resources = resource_path.read_text(encoding="utf-8")
for field in ("FileDescription", "ProductName"):
    resources, count = re.subn(rf'(VALUE "{field}", )"[^"]*"',
                               rf'\1"Crunch Cartel POS"', resources)
    if count != 1:
        raise RuntimeError(f"Could not locate the generated {field} resource.")
resource_path.write_text(resources, encoding="utf-8")
print("Crunch Cartel Windows title and icon verified at 16–256px.")
