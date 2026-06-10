# Defect Log — Digital Goods Platform

This document logs all functional, logical, and environment defects identified and resolved during the SQA testing phase of the **Digital Goods Platform**.

| Defect ID | Description | Severity | Priority | Steps to Reproduce | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|---|---|
| **BUG-001** | Missing public interface function for property counter in `LandFractionalNFT.sol` | High | High | 1. Deploy the `LandFractionalNFT` smart contract.<br>2. Call the function to query the total properties count using `getTotalProperties()`. | The contract should return the total count of registered properties. | Transaction reverts or method is undefined on the contract. | **Fixed** |
| **BUG-002** | Missing zero-fraction input validation in `LandFractionalNFT.sol` purchase function | Medium | Medium | 1. Call `purchaseFractions` on `LandFractionalNFT` with `fractionsToBuy` set to `0`. | The transaction must revert with "Purchase amount must be greater than zero". | The transaction proceeds with 0 fractions or reverts with a generic gas failure. | **Fixed** |
| **BUG-003** | State persistence leak in `SimpleWalletService` balance manager | Medium | High | 1. Instantiate `SimpleWalletService` and perform a fund lock operation of 4.0 MATIC.<br>2. Close the wallet session and open a new session.<br>3. Query the starting available balance. | The wallet service should initialize with a clean balance of 10.0 MATIC. | The new session starts with a polluted balance of 6.0 MATIC. | **Fixed** |

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
