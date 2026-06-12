# Areeba Mujtaba - Maestro E2E Testing Guide

## Responsibility from attached documents
Areeba Mujtaba is Member 1 and is responsible for E2E UI testing using Maestro YAML flows on an Android Emulator. Unit tests, Hardhat tests, API tests, integration tests, mocks, and negative function-level tests belong to other members.

Required by the test plan: minimum 5 E2E UI user flows. This folder contains 10 flows.

## Test accounts
- Land Supplier: `areebamujtaba96@gmail.com` / `12345678`
- User/Consumer: `f22bscs032@gmail.com` / `12345678`
- Electronics Supplier: `www.humairamujtaba@gmail.com` / `123456`

## Covered flows
1. Onboarding + Areeba Land Supplier login + supplier dashboard verification.
2. Registration form validation + user/supplier role UI.
3. Land Supplier dashboard asset list and action buttons.
4. Supplier asset QR code screen and export actions.
5. Wallet entry point, profile screen, and settings screen.
6. QR scanner navigation and stolen report form navigation.
7. Land Supplier notification screen navigation.
8. Land Supplier Add Asset screen, safe form filling, required documents/mint button verification.
9. User/Consumer login, marketplace verification, and notifications.
10. Electronics Supplier login, dashboard verification, and notifications.

## Before running Maestro
Make sure the app is installed on the emulator. If `flutter run` is slow, install the existing debug APK:

```powershell
C:\Users\ayaza\AppData\Local\Android\Sdk\platform-tools\adb.exe -s emulator-5554 install -r C:\fyp\testing\build\app\outputs\flutter-apk\app-debug.apk
```

Confirm the package is installed:

```powershell
C:\Users\ayaza\AppData\Local\Android\Sdk\platform-tools\adb.exe -s emulator-5554 shell cmd package list packages com.example.digitalgoods
```

Expected output:

```text
package:com.example.digitalgoods
```

## Important run note
Do not run the local folder with `maestro test tests\e2e` on one emulator. Use the sequential runner below. It waits between flows and retries once if the emulator briefly goes offline.


## Fix infrastructure issues first

If flows 01, 02, or 03 fail with `Device offline`, `UNAVAILABLE`, `device not found`, or ADB disconnection, record them as **Environment / Setup Issues**, not app defects. Use this reset command before rerunning:

```powershell
cd C:\fyp\testing
powershell -ExecutionPolicy Bypass -File tests\e2e\reset_maestro_device.ps1
```

Then rerun the suite:

```powershell
powershell -ExecutionPolicy Bypass -File tests\e2e\run_areeba_flows.ps1
```

If the reset script says the device is not online, cold boot `Pixel_9a` from Android Studio Device Manager, wait until the home screen is visible, then run the reset script again.

## Run one smoke flow first
```powershell
cd C:\fyp\testing
maestro test tests\e2e\01_smoke_onboarding_login.yaml -e SUPPLIER_EMAIL="areebamujtaba96@gmail.com" -e SUPPLIER_PASSWORD="12345678" -e USER_EMAIL="f22bscs032@gmail.com" -e USER_PASSWORD="12345678" -e ELECTRONICS_EMAIL="www.humairamujtaba@gmail.com" -e ELECTRONICS_PASSWORD="123456"
```

## Run full Areeba suite sequentially
```powershell
cd C:\fyp\testing
powershell -ExecutionPolicy Bypass -File tests\e2e\run_areeba_flows.ps1
```

## Evidence to submit
- Maestro terminal output.
- The sequential run log in `test-results\maestro-areeba-YYYYMMDD-HHMMSS.log`.
- Screenshots from `tests\e2e\screenshots` and Maestro debug folders under `C:\Users\ayaza\.maestro\tests`.
- Failing cases recorded in `test-results\defect-log.md`.
- AI usage recorded in `tests\e2e\AI_USAGE_AREEBA.md`.

## Notes
- Wallet connection opens external wallet/Reown/MetaMask UI, so these flows verify the app wallet entry point rather than automating MetaMask itself.
- Add Asset is verified through safe form entry and required UI checks. The test does not press the final blockchain mint action because that requires documents, IPFS, wallet connection, and transaction signing.
- QR verification requires a real QR code. The automated flow verifies scanner navigation; live QR verification can be demonstrated manually.
- If Maestro shows `device offline`, `UNAVAILABLE`, or `cmd: Can't find service: package`, cold boot the Pixel_9a emulator and rerun the sequential script.

