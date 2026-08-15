from __future__ import annotations

import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTECTED = {
    "src/staking/HelikonStakingVault.vy": "df7f162927a1ade8256f531ecb25da4dc4367b53",
    "tests/helpers/helikon_model.py": "40417d284c131821da5d3cb4d49222f135c3ab8b",
}
RESTRICTED = re.compile(
    r"\b(?:ctf|labs?|laboratorios?|vulnerabil(?:ity|idad|idades)|vulnerable|bugs?|exploits?|bypass|attackers?|atacantes?)\b",
    re.IGNORECASE,
)
TEXT_SUFFIXES = {".vy", ".vyi", ".py", ".md", ".json", ".yml", ".yaml", ".toml", ".txt"}


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def nonblank(path: Path) -> int:
    return sum(bool(line.strip()) for line in path.read_text(encoding="utf-8").splitlines())


def main() -> int:
    errors: list[str] = []
    for path, expected in PROTECTED.items():
        if git("hash-object", path) != expected:
            errors.append(f"{path} does not match its approved source blob")

    docs = sorted((ROOT / "docs").glob("*.md"))
    if len(docs) != 7:
        errors.append(f"expected 7 operational documents, found {len(docs)}")
    markdown = [ROOT / "README.md", ROOT / "SECURITY.md", *docs]
    diagrams = sum(path.read_text(encoding="utf-8").count("```mermaid") for path in markdown)
    if diagrams != 27:
        errors.append(f"expected 27 Mermaid diagrams, found {diagrams}")

    banner = (ROOT / "assets" / "banner.png").read_bytes()
    width, height = struct.unpack(">II", banner[16:24])
    if not banner.startswith(b"\x89PNG") or (width, height) != (1672, 941):
        errors.append("banner must be a 1672x941 PNG")

    tracked = git("ls-files").splitlines()
    excluded = {"LICENSE", "scripts/verify_release.py", *PROTECTED}
    for name in tracked:
        path = ROOT / name
        if name in excluded or path.suffix not in TEXT_SUFFIXES:
            continue
        if RESTRICTED.search(path.read_text(encoding="utf-8")):
            errors.append(f"{name} contains restricted public terminology")

    if "version = \"1.0.0\"" not in (ROOT / "pyproject.toml").read_text(encoding="utf-8"):
        errors.append("project version must be 1.0.0")
    if not git("check-ignore", "tests/private/proof.py"):
        errors.append("private evidence path must remain ignored")

    workflows = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / ".github" / "workflows").glob("*.yml"))
    for marker in ("actions/checkout@v7", "actions/setup-python@v7", "ubuntu-latest", "windows-latest"):
        if marker not in workflows:
            errors.append(f"workflow marker missing: {marker}")

    source_loc = sum(nonblank(ROOT / name) for name in tracked if Path(name).suffix in {".vy", ".vyi"})
    public_tests = sum(1 for name in tracked if name.startswith("tests/") and name.endswith(".py") for line in (ROOT / name).read_text(encoding="utf-8").splitlines() if line.startswith("def test_"))
    public_text = sum(nonblank(ROOT / name) for name in tracked if Path(name).suffix in TEXT_SUFFIXES or name == "LICENSE")
    digest = hashlib.sha256("\n".join(path.read_text(encoding="utf-8") for path in markdown).encode()).hexdigest()

    if errors:
        for error in errors:
            print(f"- {error}")
        return 1
    print(json.dumps({"protocol": "HelikonStakingProtocol", "version": "1.0.0", "contracts": len(list((ROOT / "src").rglob("*.vy"))), "source_nonblank": source_loc, "public_tests": public_tests, "public_text_nonblank": public_text, "docs": len(docs), "diagrams": diagrams, "protected_sources": len(PROTECTED), "documentation_sha256": digest}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
