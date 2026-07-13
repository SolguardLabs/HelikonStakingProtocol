
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


def main() -> int:
    files = sorted(SRC.rglob("*.vy"))
    if not files:
        raise SystemExit("no Vyper sources found")
    for source in files:
        print(f"compiling {source.relative_to(ROOT)}")
        subprocess.run([sys.executable, "-m", "vyper", str(source)], check=True, stdout=subprocess.DEVNULL)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
