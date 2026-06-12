param(
  [string]$DeviceId = "emulator-5554",
  [string]$ApkPath = "C:\fyp\testing\build\app\outputs\flutter-apk\app-debug.apk",
  [string]$PackageName = "com.example.digitalgoods"
)

$ErrorActionPreference = "Stop"
$Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $Adb)) {
  throw "ADB not found at $Adb. Check Android SDK installation."
}

Write-Host "Restarting ADB..."
& $Adb kill-server | Out-Null
& $Adb start-server | Out-Null
& $Adb wait-for-device | Out-Null
Start-Sleep -Seconds 5

$devices = (& $Adb devices) -join "`n"
Write-Host $devices
if ($devices -notmatch "$DeviceId\s+device") {
  throw "Device $DeviceId is not online. Cold boot Pixel_9a from Android Studio Device Manager, then rerun this script."
}

Write-Host "Waking device..."
& $Adb -s $DeviceId shell input keyevent 224 | Out-Null
Start-Sleep -Seconds 2

if (Test-Path $ApkPath) {
  Write-Host "Installing APK..."
  & $Adb -s $DeviceId install -r $ApkPath
} else {
  Write-Host "APK not found at $ApkPath. Skip install; run flutter build apk or flutter run if package is missing."
}

$packageCheck = (& $Adb -s $DeviceId shell cmd package list packages $PackageName) -join "`n"
if ($packageCheck -notmatch $PackageName) {
  throw "Package $PackageName is not installed. Install the APK before Maestro testing."
}

Write-Host "Device ready for Maestro: $DeviceId"
Write-Host $packageCheck
