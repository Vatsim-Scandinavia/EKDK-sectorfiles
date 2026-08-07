$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
$script:Scanner = Join-Path $script:RepositoryRoot "scripts/check_credentials.ps1"
$script:PowerShell = (Get-Process -Id $PID).Path
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:TestsRun = 0
$script:TestsFailed = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message (expected '$Expected', got '$Actual')"
    }
}

function Assert-Contains {
    param([string]$Text, [string]$Expected, [string]$Message)
    if (-not $Text.Contains($Expected)) {
        throw "$Message (missing '$Expected')"
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Unexpected, [string]$Message)
    if ($Text.Contains($Unexpected)) {
        throw "$Message (found unexpected text)"
    }
}

function Invoke-Scanner {
    param([string]$WorkingDirectory, [string[]]$Arguments)

    $processArguments = @(
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $script:Scanner
    ) + @($Arguments)
    foreach ($argument in $processArguments) {
        if ($argument.Contains('"')) {
            throw "test argument contains an unsupported quote"
        }
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:PowerShell
    $startInfo.Arguments = ($processArguments | ForEach-Object { '"' + $_ + '"' }) -join " "
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $standardOutput = $process.StandardOutput.ReadToEndAsync()
    $standardError = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $standardError.Result + $standardOutput.Result
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
}

function Invoke-Git {
    param([string]$WorkingDirectory, [string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & git -C $WorkingDirectory @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($exitCode -ne 0) {
        throw "git failed: $($output -join [Environment]::NewLine)"
    }
}

function Initialize-TestRepository {
    param([string]$Path)

    Invoke-Git $Path @("init", "--quiet")
    Invoke-Git $Path @("config", "user.name", "Credential Scanner Tests")
    Invoke-Git $Path @("config", "user.email", "scanner-tests@example.invalid")
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8)
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Test)

    $script:TestsRun++
    $directory = Join-Path ([System.IO.Path]::GetTempPath()) (
        "credential-scanner-" + [guid]::NewGuid().ToString("N")
    )
    [void][System.IO.Directory]::CreateDirectory($directory)
    try {
        & $Test $directory
        Write-Host "PASS $Name"
    }
    catch {
        $script:TestsFailed++
        Write-Host "FAIL $Name`: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Remove-Item -LiteralPath $directory -Recurse -Force
    }
}

Invoke-Test "detects required records, case variants, tabs, and spaces" {
    param($root)
    $sample = Join-Path $root "records with spaces.txt"
    Write-Utf8File $sample (
        "LastSession`tpassword`tpepper-GVABSL`n" +
        "LastSession username admin`n" +
        "server certificate 887089`n" +
        "SESSION PASSWD secret-value`n" +
        "mixed UsErNaMe example-value`n"
    )
    $result = Invoke-Scanner $root @($sample)
    Assert-Equal 1 $result.ExitCode "positive records must fail"
    Assert-Equal 5 ([regex]::Matches($result.Output, "value=\[REDACTED\]").Count) "finding count"
    Assert-Contains $result.Output "records with spaces.txt:1" "filename and line number"
    foreach ($value in "pepper-GVABSL", "admin", "887089", "secret-value", "example-value") {
        Assert-NotContains $result.Output $value "credential values must be redacted"
    }
}

Invoke-Test "ignores required negative records" {
    param($root)
    $sample = Join-Path $root "negative.conf"
    Write-Utf8File $sample (
        "The password must contain twelve characters.`n" +
        "username`npassword =`nLastSession password`n" +
        "LastSession environment production`n"
    )
    $result = Invoke-Scanner $root @($sample)
    Assert-Equal 0 $result.ExitCode "negative records must pass"
}

Invoke-Test "ignores unsupported, empty, and binary files" {
    param($root)
    $unsupported = Join-Path $root "credentials.ini"
    $empty = Join-Path $root "empty.md"
    $binary = Join-Path $root "binary.txt"
    Write-Utf8File $unsupported "session password hidden-value`n"
    [System.IO.File]::WriteAllBytes($empty, [byte[]]@())
    [System.IO.File]::WriteAllBytes($binary, [byte[]](1, 0, 2, 3))
    $result = Invoke-Scanner $root @($unsupported, $empty, $binary)
    Assert-Equal 0 $result.ExitCode "ignored inputs must pass"
    Assert-NotContains $result.Output "hidden-value" "ignored values must not be logged"
}

Invoke-Test "reports multiple findings deterministically" {
    param($root)
    $first = Join-Path $root "a.md"
    $second = Join-Path $root "b.txt"
    Write-Utf8File $first "first PASSWORD hidden-a`nthird certificate hidden-c`n"
    Write-Utf8File $second "second user hidden-b`n"
    $result = Invoke-Scanner $root @($second, $first)
    Assert-Equal 1 $result.ExitCode "multiple findings must fail"
    $lines = @(
        $result.Output -split "`r?`n" |
            Where-Object { $_.Contains("[REDACTED]") }
    )
    Assert-Equal 3 $lines.Count "finding count"
    Assert-Contains $lines[0] "a.md:1" "first deterministic result"
    Assert-Contains $lines[1] "a.md:2" "second deterministic result"
    Assert-Contains $lines[2] "b.txt:1" "third deterministic result"
    Assert-NotContains $result.Output "hidden-" "values must be redacted"
}

Invoke-Test "returns exit code 2 for operational errors" {
    param($root)
    $result = Invoke-Scanner $root @("missing.txt")
    Assert-Equal 2 $result.ExitCode "missing supported file must be an operational error"
    Assert-Contains $result.Output "credential scan error" "operational error message"
}

Invoke-Test "default mode scans staged content and ignores deleted files" {
    param($root)
    Initialize-TestRepository $root
    $staged = Join-Path $root "staged file.txt"
    $deleted = Join-Path $root "deleted.conf"
    Write-Utf8File $staged "safe initial content`n"
    Write-Utf8File $deleted "safe configuration text`n"
    Invoke-Git $root @("add", "--", "staged file.txt", "deleted.conf")
    Invoke-Git $root @("commit", "-m", "initial")
    Remove-Item -LiteralPath $deleted
    Invoke-Git $root @("add", "-u", "--", "deleted.conf")
    Write-Utf8File $staged "session user staged-secret`n"
    Invoke-Git $root @("add", "--", "staged file.txt")
    Write-Utf8File $staged "safe working tree content`n"
    $result = Invoke-Scanner $root @()
    Assert-Equal 1 $result.ExitCode "staged credential must fail"
    Assert-Contains $result.Output "staged file.txt:1" "staged filename"
    Assert-NotContains $result.Output "staged-secret" "staged value must be redacted"
    Assert-NotContains $result.Output "deleted.conf" "deleted files must be ignored"
}

Invoke-Test "all-tracked mode scans unstaged files with spaces" {
    param($root)
    Initialize-TestRepository $root
    $sample = Join-Path $root "DK AIR.prf"
    $deleted = Join-Path $root "deleted tracked.txt"
    Write-Utf8File $sample "safe initial content`n"
    Write-Utf8File $deleted "safe deleted content`n"
    Invoke-Git $root @("add", "--", "DK AIR.prf", "deleted tracked.txt")
    Invoke-Git $root @("commit", "-m", "initial")
    Write-Utf8File $sample "section certificate hidden-value`n"
    Remove-Item -LiteralPath $deleted
    $result = Invoke-Scanner $root @("-AllTracked")
    Assert-Equal 1 $result.ExitCode "all-tracked credential must fail"
    Assert-Contains $result.Output "DK AIR.prf:1" "tracked filename"
    Assert-NotContains $result.Output "hidden-value" "tracked value must be redacted"
    Assert-NotContains $result.Output "deleted tracked.txt" "deleted tracked file must be ignored"
}

if ($script:TestsFailed -gt 0) {
    Write-Host "$($script:TestsFailed) of $($script:TestsRun) tests failed." -ForegroundColor Red
    exit 1
}
Write-Host "All $($script:TestsRun) credential scanner tests passed."
exit 0
