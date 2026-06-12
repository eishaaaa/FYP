# Defect Log — Digital Goods Platform

This document logs all functional, logical, and environment defects identified and resolved during the SQA testing phase of the **Digital Goods Platform**.

| Defect ID | Description | Severity | Priority | Steps to Reproduce | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|---|---|
| **BUG-001** | Missing public interface function for property counter in `LandFractionalNFT.sol` | High | High | 1. Deploy the `LandFractionalNFT` smart contract.<br>2. Call the function to query the total properties count using `getTotalProperties()`. | The contract should return the total count of registered properties. | Transaction reverts or method is undefined on the contract. | **Fixed** |
| **BUG-002** | Missing zero-fraction input validation in `LandFractionalNFT.sol` purchase function | Medium | Medium | 1. Call `purchaseFractions` on `LandFractionalNFT` with `fractionsToBuy` set to `0`. | The transaction must revert with "Purchase amount must be greater than zero". | The transaction proceeds with 0 fractions or reverts with a generic gas failure. | **Fixed** |
| **BUG-003** | State persistence leak in `SimpleWalletService` balance manager | Medium | High | 1. Instantiate `SimpleWalletService` and perform a fund lock operation of 4.0 MATIC.<br>2. Close the wallet session and open a new session.<br>3. Query the starting available balance. | The wallet service should initialize with a clean balance of 10.0 MATIC. | The new session starts with a polluted balance of 6.0 MATIC. | **Fixed** |
| **BUG-004** | Commented out import of `keccak256` in `blockchain_service.dart` causes compilation failure | High | High | 1. Compile the Flutter project.<br>2. Observe compilation result in the blockchain package. | Compilation completes successfully. | Compilation fails due to undefined reference to `keccak256`. | **Fixed** |
| **BUG-005** | Network mismatch during wallet transaction raises a warning instead of a rejection exception | High | High | 1. Connect wallet to incorrect network (e.g. Ethereum Mainnet).<br>2. Initiate a fractional land purchase transaction. | Transaction terminates immediately with a network configuration error. | Transaction displays warning in console and opens MetaMask, causing an on-chain failure. | **Fixed** |
| **BUG-006** | ERC-1155 `safeTransferFrom` lookup crashes if 5-parameter ABI overload is absent | High | Medium | 1. Perform fraction transfer using a contract version lacking the custom 5-parameter signature. | Code falls back to standard signature without crashing. | Application crashes with a NoSuchMethodError or StateError. | **Fixed** |
| **BUG-007** | Field mapping mismatch during asset restoration (`plotArea` vs `totalArea`) | Medium | High | 1. Delete an asset document in Firestore.<br>2. Trigger self-healing restoration from the blockchain ledger. | Restored document matches current schema fields. | Restored document writes area to obsolete `plotArea` field instead of `totalArea`. | **Fixed** |
| **BUG-008** | Incomplete stolen status flags synchronization in self-healing logic | Medium | Medium | 1. Report a device as stolen on-chain.<br>2. Trigger verify and heal logic.<br>3. Navigate to device transfer screen. | All related Firestore stolen flags sync, blocking the transfer screen. | Only partial flags sync, allowing transfer check bypasses. | **Fixed** |

---

## 🛠️ Defect Resolutions

### BUG-001: Missing Public Interface Function
- **Root Cause:** The property tracking variable was marked private and the contract was missing the external getter function `getTotalProperties()` required by the integration layers.
- **Fix:** Added the public view function `getTotalProperties()` to `LandFractionalNFT.sol` to safely return the array length of created properties.

### BUG-002: Zero-Fraction Input Validation
- **Root Cause:** Missing boundary validation check on the input parameter `fractionsToBuy` inside the `purchaseFractions` method.
- **Fix:** Added a `require(fractionsToBuy > 0, "Purchase amount must be greater than zero")` statement at the beginning of the function in `LandFractionalNFT.sol`.

### BUG-003: State Persistence Leak
- **Root Cause:** The `SimpleWalletService` class design lacked a state-reset mechanism, causing active session data (available and locked balances) to persist in memory across separate operations.
- **Fix:** Implemented a state cleanup and initialization method inside `SimpleWalletService` to reset balances back to default values (10.0 available, 0.0 locked) upon session start.

### BUG-004: Missing keccak256 Import
- **Root Cause:** The required crypto import block `show keccak256` was commented out in `blockchain_service.dart`.
- **Fix:** Restored the import path `import 'package:web3dart/crypto.dart' show keccak256;` to resolve compilation.

### BUG-005: Improper Wrong Network Check Handling
- **Root Cause:** Code logged a console warning instead of throwing a validation exception when user was connected to an incompatible network chain.
- **Fix:** Changed console warning logic to an explicit `throw Exception(...)` error in `blockchain_service.dart` to reject transactions prior to opening the wallet.

### BUG-006: ERC-1155 safeTransferFrom Crash
- **Root Cause:** Code assumed a 5-parameter overload of `safeTransferFrom` was always present in the ABI, failing when it was not.
- **Fix:** Added fallback verification checking parameter length to choose the standard signature if the custom overload is absent.

### BUG-007: Property Restoration Field Mismatch
- **Root Cause:** The restoration code used `plotArea` when writing property metadata back to Firestore, whereas the schema requires `totalArea`.
- **Fix:** Replaced the target field key with `totalArea` inside the restoration map in `blockchain_service.dart`.

### BUG-008: Incomplete Stolen Flag Sync
- **Root Cause:** Self-healing code only set `reportedStolen` and `isStolen` fields, whereas `transfer_screen.dart` queries `isStolenReported`.
- **Fix:** Synced all three flags (`isStolenReported`, `isStolen`, and `reportedStolen`) in the Firestore document during device healing.

# Defect Log - Digital Goods E2E UI Testing

## App Defects

Only confirmed application behavior problems should be added here. Emulator, ADB, package manager, or Maestro connection failures are setup issues and should not be counted as app bugs.

| TBD | TBD | TBD | TBD | Add only after a flow reaches the app screen and confirms an app behavior problem. | TBD | TBD | TBD | Open | Areeba |

## Environment / Setup Issues

| ENV-E2E-001 | 01_smoke_onboarding_login, 02_registration_validation, 03_supplier_dashboard_assets | Android emulator / ADB stability | Maestro result showed `Device offline` / ADB disconnection during run. | Setup issue, not an application defect. | Cold boot Pixel_9a, run `tests\e2e\reset_maestro_device.ps1`, then rerun `tests\e2e\run_areeba_flows.ps1`. | Open until rerun passes | Areeba |

## Severity Guide

- Critical: App crash, security issue, data loss, or impossible core workflow.
- High: Major user flow blocked after stable environment is confirmed.
- Medium: Important feature partially broken.
- Low: UI text, visual, or minor navigation issue.

## Status Guide

- Open: Needs fix or rerun.
- Fixed: Fixed and verified.
- Deferred: Known limitation accepted for this release.
- Not an app defect: Environment/setup issue only.
