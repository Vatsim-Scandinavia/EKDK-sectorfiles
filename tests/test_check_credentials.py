from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCANNER = REPOSITORY_ROOT / "scripts" / "check_credentials.py"


class CredentialScannerTests(unittest.TestCase):
    def run_scanner(
        self, working_directory: Path, *arguments: str
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCANNER), *arguments],
            cwd=working_directory,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_detects_required_records_case_and_delimiters(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sample = root / "records with spaces.txt"
            sample.write_text(
                "LastSession\tpassword\tpepper-GVABSL\n"
                "LastSession username admin\n"
                "server certificate 887089\n"
                "SESSION PASSWD secret-value\n"
                "mixed UsErNaMe example-value\n",
                encoding="utf-8",
            )

            result = self.run_scanner(root, str(sample))

            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr.count("value=[REDACTED]"), 5)
            self.assertIn("records with spaces.txt:1", result.stderr)
            for value in (
                "pepper-GVABSL",
                "admin",
                "887089",
                "secret-value",
                "example-value",
            ):
                self.assertNotIn(value, result.stdout + result.stderr)

    def test_ignores_required_negative_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sample = root / "negative.conf"
            sample.write_text(
                "The password must contain twelve characters.\n"
                "username\n"
                "password =\n"
                "LastSession password\n"
                "LastSession environment production\n",
                encoding="utf-8",
            )

            result = self.run_scanner(root, str(sample))

            self.assertEqual(result.returncode, 0)
            self.assertIn("Credential scan passed", result.stdout)

    def test_ignores_unsupported_empty_and_binary_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            unsupported = root / "credentials.ini"
            empty = root / "empty.md"
            binary = root / "binary.txt"
            unsupported.write_text("session password hidden-value\n", encoding="utf-8")
            empty.write_bytes(b"")
            binary.write_bytes(b"session password hidden-value\0binary")

            result = self.run_scanner(
                root, str(unsupported), str(empty), str(binary)
            )

            self.assertEqual(result.returncode, 0)
            self.assertNotIn("hidden-value", result.stdout + result.stderr)

    def test_reports_multiple_findings_in_deterministic_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            second = root / "b.txt"
            first = root / "a.md"
            second.write_text("second user hidden-b\n", encoding="utf-8")
            first.write_text(
                "first PASSWORD hidden-a\nthird certificate hidden-c\n",
                encoding="utf-8",
            )

            result = self.run_scanner(root, str(second), str(first))

            self.assertEqual(result.returncode, 1)
            lines = [line for line in result.stderr.splitlines() if "[REDACTED]" in line]
            self.assertEqual(len(lines), 3)
            self.assertIn("a.md:1", lines[0])
            self.assertIn("a.md:2", lines[1])
            self.assertIn("b.txt:1", lines[2])
            self.assertNotIn("hidden-", result.stdout + result.stderr)

    def test_returns_operational_error_for_missing_supported_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_scanner(root, "missing.txt")

            self.assertEqual(result.returncode, 2)
            self.assertIn("credential scan error", result.stderr)

    def test_default_mode_scans_staged_content_and_ignores_deleted_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self._init_repository(root)
            staged = root / "staged file.txt"
            deleted = root / "deleted.conf"
            staged.write_text("safe initial content\n", encoding="utf-8")
            deleted.write_text("safe configuration text\n", encoding="utf-8")
            self._git(root, "add", "--", staged.name, deleted.name)
            self._git(root, "commit", "-m", "initial")
            deleted.unlink()
            self._git(root, "add", "-u", "--", deleted.name)
            staged.write_text("session user staged-secret\n", encoding="utf-8")
            self._git(root, "add", "--", staged.name)
            staged.write_text("safe working tree content\n", encoding="utf-8")

            result = self.run_scanner(root)

            self.assertEqual(result.returncode, 1)
            self.assertIn("staged file.txt:1", result.stderr)
            self.assertNotIn("staged-secret", result.stderr)
            self.assertNotIn("deleted.conf", result.stderr)

    def test_all_tracked_scans_files_with_spaces(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self._init_repository(root)
            sample = root / "tracked credentials.conf"
            sample.write_text("section certificate hidden-value\n", encoding="utf-8")
            self._git(root, "add", "--", sample.name)

            result = self.run_scanner(root, "--all-tracked")

            self.assertEqual(result.returncode, 1)
            self.assertIn("tracked credentials.conf:1", result.stderr)
            self.assertNotIn("hidden-value", result.stderr)

    def _init_repository(self, root: Path) -> None:
        self._git(root, "init", "--quiet")
        self._git(root, "config", "user.name", "Credential Scanner Tests")
        self._git(root, "config", "user.email", "scanner-tests@example.invalid")

    def _git(self, root: Path, *arguments: str) -> None:
        subprocess.run(
            ["git", *arguments],
            cwd=root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )


if __name__ == "__main__":
    unittest.main()
