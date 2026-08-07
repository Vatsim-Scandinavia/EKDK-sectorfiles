[CmdletBinding()]
param(
    [switch]$AllTracked,

    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Files
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:ScannedExtensions = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($extension in ".conf", ".md", ".txt") {
    [void]$script:ScannedExtensions.Add($extension)
}

$script:RecordPattern = [regex]::new(
    '^[ \t]*(?<identifier>\S+)[ \t]+(?<field>username|user|password|passwd|certificate)[ \t]+(?<value>\S+)[ \t]*$',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
)
$script:Utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Test-EligibleFile {
    param([string]$Filename)

    return $script:ScannedExtensions.Contains(
        [System.IO.Path]::GetExtension($Filename)
    )
}

function ConvertTo-SafeLogText {
    param([string]$Value)

    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $Value.ToCharArray()) {
        if ([char]::IsControl($character)) {
            [void]$builder.AppendFormat("\u{0:x4}", [int]$character)
        }
        else {
            [void]$builder.Append($character)
        }
    }
    return $builder.ToString()
}

function Invoke-GitBytes {
    param([string]$Arguments)

    $git = Get-Command git -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $git.Source
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $errorTask = $process.StandardError.ReadToEndAsync()
    $stream = [System.IO.MemoryStream]::new()
    $process.StandardOutput.BaseStream.CopyTo($stream)
    $process.WaitForExit()
    $errorText = $errorTask.Result.Trim()

    if ($process.ExitCode -ne 0) {
        if ($errorText) {
            throw "git command failed: $errorText"
        }
        throw "git command failed with exit code $($process.ExitCode)"
    }

    Write-Output -NoEnumerate $stream.ToArray()
}

function ConvertFrom-NulDelimitedText {
    param([byte[]]$Content)

    $text = $script:Utf8.GetString($Content)
    return @($text.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries))
}

function Get-SortedEligiblePaths {
    param([byte[]]$Content)

    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($path in ConvertFrom-NulDelimitedText $Content) {
        if (Test-EligibleFile $path) {
            $paths.Add($path)
        }
    }
    $paths.Sort([System.StringComparer]::Ordinal)
    return $paths
}

function Get-StagedInputs {
    $changedPaths = Get-SortedEligiblePaths (
        Invoke-GitBytes "diff --cached --name-only --diff-filter=ACMRT --find-renames --find-copies -z"
    )
    $index = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::Ordinal
    )

    foreach ($record in ConvertFrom-NulDelimitedText (Invoke-GitBytes "ls-files --stage -z")) {
        $separator = $record.IndexOf([char]9)
        if ($separator -lt 0) {
            continue
        }

        $metadata = $record.Substring(0, $separator)
        $path = $record.Substring($separator + 1)
        if ($metadata -match '^[0-9]+ (?<object>[0-9a-fA-F]+) 0$') {
            $index[$path] = $Matches.object.ToLowerInvariant()
        }
    }

    foreach ($path in $changedPaths) {
        if (-not $index.ContainsKey($path)) {
            throw "could not resolve staged content for $(ConvertTo-SafeLogText $path)"
        }
        $objectId = $index[$path]
        if ($objectId -notmatch '^[0-9a-f]+$') {
            throw "invalid staged object identifier"
        }
        [pscustomobject]@{
            Filename = $path
            Content = Invoke-GitBytes "cat-file blob $objectId"
        }
    }
}

function Get-TrackedInputs {
    foreach ($path in Get-SortedEligiblePaths (Invoke-GitBytes "ls-files -z")) {
        $fullPath = [System.IO.Path]::GetFullPath($path)
        if (-not [System.IO.File]::Exists($fullPath)) {
            continue
        }
        [pscustomobject]@{
            Filename = $path
            Content = [System.IO.File]::ReadAllBytes($fullPath)
        }
    }
}

function Get-WorkingTreeInputs {
    param([string[]]$Filenames)

    $uniquePaths = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($filename in $Filenames) {
        if (Test-EligibleFile $filename) {
            [void]$uniquePaths.Add($filename)
        }
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $uniquePaths) {
        $paths.Add($path)
    }
    $paths.Sort([System.StringComparer]::Ordinal)

    foreach ($path in $paths) {
        [pscustomobject]@{
            Filename = $path
            Content = [System.IO.File]::ReadAllBytes(
                [System.IO.Path]::GetFullPath($path)
            )
        }
    }
}

function Find-CredentialRecords {
    param(
        [string]$Filename,
        [byte[]]$Content
    )

    if ($Content -contains [byte]0) {
        return
    }

    try {
        $text = $script:Utf8.GetString($Content)
    }
    catch [System.Text.DecoderFallbackException] {
        return
    }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) {
        $text = $text.Substring(1)
    }

    $lineNumber = 0
    foreach ($line in [regex]::Split($text, "\r\n|\n|\r")) {
        $lineNumber++
        $match = $script:RecordPattern.Match($line)
        if ($match.Success) {
            [pscustomobject]@{
                Filename = $Filename
                LineNumber = $lineNumber
                Identifier = $match.Groups["identifier"].Value
                Field = $match.Groups["field"].Value
            }
        }
    }
}

try {
    $providedFiles = @(
        $Files | Where-Object { -not [string]::IsNullOrEmpty($_) }
    )
    $fileCount = $providedFiles.Count
    if ($AllTracked -and $fileCount -gt 0) {
        throw "-AllTracked cannot be combined with file arguments"
    }

    if ($AllTracked) {
        $inputs = @(Get-TrackedInputs)
    }
    elseif ($fileCount -gt 0) {
        $inputs = @(Get-WorkingTreeInputs $providedFiles)
    }
    else {
        $inputs = @(Get-StagedInputs)
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($inputFile in $inputs) {
        foreach ($finding in Find-CredentialRecords $inputFile.Filename $inputFile.Content) {
            $findings.Add($finding)
        }
    }
}
catch {
    [Console]::Error.WriteLine("credential scan error: $($_.Exception.Message)")
    exit 2
}

if ($findings.Count -eq 0) {
    [Console]::Out.WriteLine("Credential scan passed: no credential-like records found.")
    exit 0
}

[Console]::Error.WriteLine("Credential scan failed: credential-like records were found.")
foreach ($finding in $findings) {
    $filename = ConvertTo-SafeLogText $finding.Filename
    $identifier = ConvertTo-SafeLogText $finding.Identifier
    $field = ConvertTo-SafeLogText $finding.Field
    [Console]::Error.WriteLine(
        "${filename}:$($finding.LineNumber): identifier=$identifier field=$field value=[REDACTED]"
    )
}
[Console]::Error.WriteLine(
    "Remove the credential, replace it with a safe placeholder, or rewrite " +
    "non-sensitive documentation so it is not shaped like a credential record."
)
exit 1
