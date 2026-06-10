# ============================================================
# SQA Evidence Log Generator - Hardhat Smart Contract Tests
# Digital Goods Platform | Kinnaird College for Women
# Member 2: Eisha tur Raazia (F22BSCS014)
# ============================================================

$LogFile = "$PSScriptRoot\hardhat_test_results.log"
$ProjectDir = "d:\fyp\digital-goods-blockchain"

# --- Collect Environment Info ---
$Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$MachineUser   = $env:USERNAME
$OSVersion     = (Get-CimInstance Win32_OperatingSystem).Caption
$NodeVersion   = (node -v 2>&1)
$NPMVersion    = (npm -v 2>&1)
$HardhatVersion= (npx hardhat --version 2>&1 | Select-String "hardhat" | Select-Object -First 1)
if (-not $HardhatVersion) { $HardhatVersion = (npx hardhat --version 2>&1) }
$GitHash       = (git -C $ProjectDir rev-parse HEAD 2>&1)
$GitBranch     = (git -C $ProjectDir rev-parse --abbrev-ref HEAD 2>&1)
$GitMsg        = (git -C $ProjectDir log -1 --pretty="%s" 2>&1)

# --- Write Header ---
$Header = @"
======================================================================
  SQA PROJECT - SMART CONTRACT TEST EXECUTION LOG
  Digital Goods: Bridging Physical to Digital Space using NFTs
======================================================================
  Institution   : Kinnaird College for Women, Lahore
  Course        : Software Quality Assurance and Testing (SQA)
  Supervisor    : Dr. Sidra Zafar
  Executed By   : Eisha tur Raazia  |  Roll No: F22BSCS014
  Testing Role  : Logic & Unit Testing Specialist (Hardhat)
----------------------------------------------------------------------
  Run Timestamp : $Timestamp
  Machine User  : $MachineUser
  OS            : $OSVersion
  Node.js       : $NodeVersion
  npm           : $NPMVersion
  Hardhat       : $HardhatVersion
----------------------------------------------------------------------
  Git Commit    : $GitHash
  Git Branch    : $GitBranch
  Commit Msg    : $GitMsg
----------------------------------------------------------------------
  Test Script   : digital-goods-blockchain\test\test-contracts.js
  Contracts     : contracts\ElectronicsNFT.sol
                  contracts\LandFractionalNFT.sol
  Network       : Hardhat Local Node (Chain ID: 31337)
  Framework     : Mocha + Chai (via Hardhat)
======================================================================

FULL TEST EXECUTION OUTPUT:
----------------------------------------------------------------------
"@

Set-Content -Path $LogFile -Value $Header -Encoding UTF8

# --- Run Hardhat Tests and Append Output ---
$StartTime = Get-Date
Push-Location $ProjectDir
$TestOutput = npx hardhat test 2>&1
Pop-Location
$EndTime   = Get-Date
$Duration  = ($EndTime - $StartTime).TotalSeconds

Add-Content -Path $LogFile -Value $TestOutput -Encoding UTF8

# --- Parse Pass/Fail counts from output ---
$PassLine  = $TestOutput | Where-Object { $_ -match "passing" } | Select-Object -Last 1
$FailLine  = $TestOutput | Where-Object { $_ -match "failing" } | Select-Object -Last 1
$PendLine  = $TestOutput | Where-Object { $_ -match "pending" } | Select-Object -Last 1

$PassCount = if ($PassLine -match "(\d+) passing") { $Matches[1] } else { "0" }
$FailCount = if ($FailLine -match "(\d+) failing") { $Matches[1] } else { "0" }
$PendCount = if ($PendLine -match "(\d+) pending") { $Matches[1] } else { "0" }
$TotalTests = [int]$PassCount + [int]$FailCount + [int]$PendCount
$PassRate  = if ($TotalTests -gt 0) { [math]::Round(([int]$PassCount / $TotalTests) * 100, 1) } else { 0 }

# --- Write Summary Footer ---
$Footer = @"

======================================================================
  EXECUTION SUMMARY
======================================================================
  Total Tests Executed   : $TotalTests
  Tests Passed           : $PassCount
  Tests Failed           : $FailCount
  Tests Pending/Skipped  : $PendCount
  Pass Rate              : $PassRate%
  Total Execution Time   : $([math]::Round($Duration, 2)) seconds
  Exit Status            : $(if ($FailCount -eq "0") { "SUCCESS - All tests passed" } else { "FAILURE - $FailCount test(s) failed" })
======================================================================
  Log saved to: $LogFile
======================================================================
"@

Add-Content -Path $LogFile -Value $Footer -Encoding UTF8

# --- Print summary to console too ---
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Hardhat Test Log Generated Successfully" -ForegroundColor Green
Write-Host "  Tests Passed  : $PassCount / $TotalTests  (Pass Rate: $PassRate%)" -ForegroundColor Green
Write-Host "  Duration      : $([math]::Round($Duration, 2)) seconds" -ForegroundColor Yellow
Write-Host "  Log saved to  : $LogFile" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
