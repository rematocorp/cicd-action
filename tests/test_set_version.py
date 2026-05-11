"""Unit tests for scripts/set_version.py."""

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SETTER = REPO_ROOT / "scripts" / "set_version.py"


def run_setter(*args):
    return subprocess.run(
        [sys.executable, str(SETTER), *args],
        capture_output=True,
        text=True,
    )


SIMPLE_PKG = '''{
  "name": "frontend",
  "version": "1.2.3",
  "private": true
}
'''

SIMPLE_PKG_2_0_0 = '''{
  "name": "frontend",
  "version": "2.0.0",
  "private": true
}
'''


def test_sets_version(tmp_path):
    pkg = tmp_path / "package.json"
    pkg.write_text(SIMPLE_PKG)
    result = run_setter("2.0.0", str(pkg))
    assert result.returncode == 0, result.stderr
    assert pkg.read_text() == SIMPLE_PKG_2_0_0


def test_preserves_formatting_and_other_fields(tmp_path):
    pkg = tmp_path / "package.json"
    original = '''{
    "name":"weird-spacing",
    "version" :  "0.0.1"  ,
    "dependencies": {
        "react": "^18.0.0"
    }
}
'''
    expected = '''{
    "name":"weird-spacing",
    "version" :  "9.9.9"  ,
    "dependencies": {
        "react": "^18.0.0"
    }
}
'''
    pkg.write_text(original)
    result = run_setter("9.9.9", str(pkg))
    assert result.returncode == 0, result.stderr
    assert pkg.read_text() == expected


def test_writes_multiple_files(tmp_path):
    a = tmp_path / "a" / "package.json"
    b = tmp_path / "b" / "package.json"
    for p in (a, b):
        p.parent.mkdir(parents=True)
        p.write_text(SIMPLE_PKG)
    result = run_setter("2.0.0", str(a), str(b))
    assert result.returncode == 0, result.stderr
    assert a.read_text() == SIMPLE_PKG_2_0_0
    assert b.read_text() == SIMPLE_PKG_2_0_0


def test_accepts_prerelease(tmp_path):
    pkg = tmp_path / "package.json"
    pkg.write_text(SIMPLE_PKG)
    result = run_setter("1.2.4-beta.1", str(pkg))
    assert result.returncode == 0, result.stderr
    assert '"version": "1.2.4-beta.1"' in pkg.read_text()


def test_rejects_invalid_version(tmp_path):
    pkg = tmp_path / "package.json"
    pkg.write_text(SIMPLE_PKG)
    result = run_setter("not-a-version", str(pkg))
    assert result.returncode == 1
    assert "invalid semver" in result.stderr
    assert pkg.read_text() == SIMPLE_PKG  # untouched


def test_rejects_two_part_version(tmp_path):
    pkg = tmp_path / "package.json"
    pkg.write_text(SIMPLE_PKG)
    result = run_setter("1.2", str(pkg))
    assert result.returncode == 1
    assert "invalid semver" in result.stderr


def test_missing_version_field_errors(tmp_path):
    pkg = tmp_path / "package.json"
    pkg.write_text('{"name": "no-version"}\n')
    result = run_setter("1.2.3", str(pkg))
    assert result.returncode == 1
    assert "no top-level 'version' field" in result.stderr


def test_no_args_prints_usage():
    result = run_setter()
    assert result.returncode == 2
    assert "usage:" in result.stderr.lower()
