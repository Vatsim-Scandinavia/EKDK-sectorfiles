# Credential scanning

This repository checks selected text files for records shaped as three
whitespace-delimited columns: an identifier or section, a sensitive field, and
a non-empty value. The field match is case-insensitive. The sensitive fields
are `username`, `user`, `password`, `passwd`, and `certificate`.

Only files ending in `.conf`, `.md`, or `.txt` are scanned. Binary files are
ignored, and detected values are always displayed as `[REDACTED]`.

## Local pre-commit hook

Enable the version-controlled hook once in your clone:

```bash
git config core.hooksPath .githooks
```

The hook uses PowerShell to run `scripts/check_credentials.ps1 -AllTracked`. It
prefers PowerShell 7 (`pwsh`) and falls back to Windows PowerShell
(`powershell.exe`). Every tracked file with a supported extension is examined,
including tracked working-tree changes that have not been staged. A
credential-like record blocks the commit.

## Manual use

Scan staged content with Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_credentials.ps1
```

Scan specific working-tree files (filenames containing spaces are supported):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_credentials.ps1 "path/to/example file.txt"
```

Scan every tracked file with a supported extension, as CI does:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_credentials.ps1 -AllTracked
```

With PowerShell 7, replace `powershell` with `pwsh` in these commands.

## False positives

Do not add broad exclusions. First verify that the record is non-sensitive. If
it is documentation, rewrite it as prose or replace the value with a clearly
safe placeholder while avoiding the three-column credential-record shape. If
the format cannot be changed, propose a narrowly scoped, documented exception
for review; the scanner currently has no suppression directives because none
are needed by the repository.
