# ============================================================
# SQA Evidence Log Generator - Flutter Unit Tests
# Digital Goods Platform | Kinnaird College for Women
# Member 2: Eisha tur Raazia (F22BSCS014)
# ============================================================

$LogFile    = "$PSScriptRoot\flutter_unit_test_results.log"
$ProjectDir = "d:\fyp\digitalgoods"

# --- Collect Environment Info ---
$Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$MachineUser    = $env:USERNAME
$OSVersion      = (Get-CimInstance Win32_OperatingSystem).Caption
$FlutterVersion = (flutter --version 2>&1) | Select-Object -First 1
$DartVersion    = (dart --version 2>&1) | Select-Object -First 1
$GitHash        = (git -C $ProjectDir rev-parse HEAD 2>&1)
$GitBranch      = (git -C $ProjectDir rev-parse --abbrev-ref HEAD 2>&1)
$GitMsg         = (git -C $ProjectDir log -1 --pretty=format:"%s" 2>&1)

# --- Build header lines individually to avoid here-string issues ---
$Lines = @()
$Lines += "======================================================================"
$Lines += "  SQA PROJECT - FLUTTER UNIT TEST EXECUTION LOG"
$Lines += "  Digital Goods: Bridging Physical to Digital Space using NFTs"
$Lines += "======================================================================"
$Lines += "  Institution   : Kinnaird College for Women, Lahore"
$Lines += "  Course        : Software Quality Assurance and Testing (SQA)"
$Lines += "  Supervisor    : Dr. Sidra Zafar"
$Lines += "  Executed By   : Eisha tur Raazia  |  Roll No: F22BSCS014"
$Lines += "  Testing Role  : Logic and Unit Testing Specialist (Flutter Test)"
$Lines += "----------------------------------------------------------------------"
$Lines += "  Run Timestamp : $Timestamp"
$Lines += "  Machine User  : $MachineUser"
$Lines += "  OS            : $OSVersion"
$Lines += "  Flutter       : $FlutterVersion"
$Lines += "  Dart          : $DartVersion"
$Lines += "----------------------------------------------------------------------"
$Lines += "  Git Commit    : $GitHash"
$Lines += "  Git Branch    : $GitBranch"
$Lines += "  Commit Msg    : $GitMsg"
$Lines += "----------------------------------------------------------------------"
$Lines += "  Test Script   : digitalgoods\test\digitalgoods_unit_test.dart"
$Lines += "  Target Files  : wallet_service.dart"
$Lines += "                  ipfs_service.dart"
$Lines += "                  explorer_service.dart"
$Lines += "  Framework     : flutter_test (Dart Test Runner)"
$Lines += "======================================================================"
$Lines += ""
$Lines += "FULL TEST EXECUTION OUTPUT:"
$Lines += "----------------------------------------------------------------------"

Set-Content -Path $LogFile -Value $Lines -Encoding UTF8

# --- Run Flutter Tests and Append Output ---
$StartTime  = Get-Date
Push-Location $ProjectDir
$TestOutput = flutter test test/digitalgoods_unit_test.dart 2>&1
Pop-Location
$EndTime  = Get-Date
$Duration = ($EndTime - $StartTime).TotalSeconds

# Filter out noisy dependency resolution lines
$CleanOutput = $TestOutput | Where-Object {
    ($_ -notmatch "available\)$") -and
    ($_ -notmatch "packages have newer") -and
    ($_ -notmatch "flutter pub outdated") -and
    ($_ -notmatch "Downloading packages") -and
    ($_ -notmatch "Resolving dependencies")
}

Add-Content -Path $LogFile -Value $CleanOutput -Encoding UTF8

# --- Parse counts from output ---
$LastLine   = $TestOutput | Where-Object { $_ -match "\+" } | Select-Object -Last 1
$PassCount  = if ($LastLine -match "\+(\d+)") { $Matches[1] } else { "0" }
$FailLine   = $TestOutput | Where-Object { $_ -match "\-(\d+)" } | Select-Object -Last 1
$FailCount  = if ($FailLine -match "\-(\d+)") { $Matches[1] } else { "0" }
$TotalTests = [int]$PassCount + [int]$FailCount
$PassRate   = if ($TotalTests -gt 0) { [math]::Round(([int]$PassCount / $TotalTests) * 100, 1) } else { 0 }
$Status     = if ([int]$FailCount -eq 0) { "SUCCESS - All tests passed" } else { "FAILURE - $FailCount test(s) failed" }

# --- Write Summary Footer ---
$Footer = @()
$Footer += ""
$Footer += "======================================================================"
$Footer += "  EXECUTION SUMMARY"
$Footer += "======================================================================"
$Footer += "  Total Tests Executed   : $TotalTests"
$Footer += "  Tests Passed           : $PassCount"
$Footer += "  Tests Failed           : $FailCount"
$Footer += "  Pass Rate              : $PassRate%"
$Footer += "  Total Execution Time   : $([math]::Round($Duration, 2)) seconds"
$Footer += "----------------------------------------------------------------------"
$Footer += "  Test Groups Covered    : 3"
$Footer += "    Group 1 - SimpleWalletService Balance and Escrow Tests  (7 tests)"
$Footer += "    Group 2 - IPFSService Metadata and Utilities Tests      (7 tests)"
$Footer += "    Group 3 - ExplorerService Logic and Helper Tests        (3 tests)"
$Footer += "----------------------------------------------------------------------"
$Footer += "  Modules Tested:"
$Footer += "    wallet_service.dart   - Escrow lockFunds, unlockFunds, consumeLockedFunds"
$Footer += "    ipfs_service.dart     - URL formatting, hash extraction, metadata builders"
$Footer += "    explorer_service.dart - Wei-to-MATIC BigInt precision conversions"
$Footer += "----------------------------------------------------------------------"
$Footer += "  Exit Status            : $Status"
$Footer += "======================================================================"
$Footer += "  Log saved to: $LogFile"
$Footer += "======================================================================"

Add-Content -Path $LogFile -Value $Footer -Encoding UTF8

# --- Print summary to console ---
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Flutter Unit Test Log Generated Successfully" -ForegroundColor Green
Write-Host "  Tests Passed  : $PassCount / $TotalTests  (Pass Rate: $PassRate%)" -ForegroundColor Green
Write-Host "  Duration      : $([math]::Round($Duration, 2)) seconds" -ForegroundColor Yellow
Write-Host "  Log saved to  : $LogFile" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
