param(
  [string]$SupplierEmail = "areebamujtaba96@gmail.com",
  [string]$SupplierPassword = "12345678",
  [string]$UserEmail = "f22bscs032@kinnaird.edu.pk",
  [string]$UserPassword = "12345678",
  [string]$ElectronicsEmail = "www.humairamujtaba123@gmail.com",
  [string]$ElectronicsPassword = "123456",
  [string]$DeviceId = "emulator-5554"
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$ResultsDir = Join-Path $ProjectRoot "test-results"
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $ResultsDir "maestro-areeba-$Stamp.log"
$Flows = Get-ChildItem -Path $PSScriptRoot -Filter "*.yaml" | Sort-Object Name
$Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
$PackageName = "com.example.digitalgoods"

function Test-DeviceReady {
  if (-not (Test-Path $Adb)) { return $false }
  $devices = (& $Adb devices) -join "`n"
  if ($devices -notmatch "$DeviceId\s+device") { return $false }
  $pkg = (& $Adb -s $DeviceId shell cmd package list packages $PackageName) -join "`n"
  return ($pkg -match $PackageName)
}

function Wait-ForAndroidDevice {
  if (-not (Test-Path $Adb)) {
    Start-Sleep -Seconds 5
    return
  }

  & $Adb wait-for-device | Out-Null
  Start-Sleep -Seconds 3
  $devices = (& $Adb devices) -join "`n"

  if ($devices -match "$DeviceId\s+offline" -or $devices -notmatch "$DeviceId\s+device") {
    "ADB device is offline/missing. Restarting ADB before retry..." | Tee-Object -FilePath $LogFile -Append
    & $Adb kill-server | Out-Null
    & $Adb start-server | Out-Null
    & $Adb wait-for-device | Out-Null
    Start-Sleep -Seconds 8
  }

  & $Adb -s $DeviceId shell input keyevent 224 | Out-Null
  Start-Sleep -Seconds 3
}

"Areeba Mujtaba Maestro E2E run started $(Get-Date -Format s)" | Tee-Object -FilePath $LogFile
"Project: $ProjectRoot" | Tee-Object -FilePath $LogFile -Append
"Device note: keep only one Android emulator/device attached while running this script." | Tee-Object -FilePath $LogFile -Append
"" | Tee-Object -FilePath $LogFile -Append

if (-not (Test-DeviceReady)) {
  "PRECHECK FAILED: $DeviceId is not online or $PackageName is not installed." | Tee-Object -FilePath $LogFile -Append
  "Run: powershell -ExecutionPolicy Bypass -File tests\e2e\reset_maestro_device.ps1" | Tee-Object -FilePath $LogFile -Append
  exit 2
}

$failed = 0
foreach ($flow in $Flows) {
  "===== RUNNING $($flow.Name) =====" | Tee-Object -FilePath $LogFile -Append
  $passed = $false

  for ($attempt = 1; $attempt -le 2 -and -not $passed; $attempt++) {
    Wait-ForAndroidDevice
    "Attempt $attempt of 2" | Tee-Object -FilePath $LogFile -Append

    maestro test $flow.FullName `
      -e SUPPLIER_EMAIL="$SupplierEmail" `
      -e SUPPLIER_PASSWORD="$SupplierPassword" `
      -e USER_EMAIL="$UserEmail" `
      -e USER_PASSWORD="$UserPassword" `
      -e ELECTRONICS_EMAIL="$ElectronicsEmail" `
      -e ELECTRONICS_PASSWORD="$ElectronicsPassword" 2>&1 | Tee-Object -FilePath $LogFile -Append

    if ($LASTEXITCODE -eq 0) {
      $passed = $true
      "PASSED: $($flow.Name)" | Tee-Object -FilePath $LogFile -Append
    } elseif ($attempt -lt 2) {
      "Retrying $($flow.Name) after emulator/device wait..." | Tee-Object -FilePath $LogFile -Append
      Start-Sleep -Seconds 12
    }
  }

  if (-not $passed) {
    $failed++
    "FAILED: $($flow.Name)" | Tee-Object -FilePath $LogFile -Append
  }
  "" | Tee-Object -FilePath $LogFile -Append
}

"Areeba Mujtaba Maestro E2E run finished $(Get-Date -Format s)" | Tee-Object -FilePath $LogFile -Append
"Failures: $failed / $($Flows.Count)" | Tee-Object -FilePath $LogFile -Append
"Log file: $LogFile" | Tee-Object -FilePath $LogFile -Append

if ($failed -gt 0) { exit 1 }
exit 0
