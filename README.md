# Digital Goods Platform — SQA Automated Test Suite

This repository contains the Software Quality Assurance (SQA) automated testing deliverables for the **Digital Goods Platform** (a decentralized application that tokenizes land as fractional interests and electronics as authenticity certificates on the Polygon blockchain).

## 👥 SQA Project Team

- **Areeba Mujtaba (F22BSCS032):** E2E UI Testing Specialist (Maestro)
- **Eisha tur Raazia (F22BSCS014):** Logic & Unit Testing Specialist (Solidity + Flutter)
- **Zainub Rashid (F22BSCS003):** API, Integration & Edge-Case Specialist (Flutter + Mocks)

**Supervisor:** Dr. Sidra Zafar  
**Institution:** Department of Computer Science, Kinnaird College for Women, Lahore  

---

## 📂 Repository Structure

- `/docs/`
  - `Final_QA_Report.md` / `Final_QA_Report.docx`: The final, consolidated QA report including execution summaries, AI usage logs, defect logging, and reflections.
  - `test-plan.md` / `TestPlan_DigitalGoods.docx`: Initial SQA test planning and strategies.
  - `Testing_Work_Distribution.md` / `Testing_Work_Distribution.docx`: Breakdown of team member responsibilities.
- `/tests/`
  - `/tests/unit/test-contracts.js`: Smart contract automated unit tests.
  - `/tests/unit/digitalgoods_unit_test.dart`: Core Dart services automated unit tests.
- `/test-results/`
  - `defect-log.md`: Formal log mapping identified software defects, severities, and resolutions.
  - `/test-results/logs/hardhat_test_results.log`: Verified execution terminal output for smart contracts.
  - `/test-results/logs/flutter_unit_test_results.log`: Verified execution terminal output for Flutter unit tests.
  - `generate_hardhat_log.ps1` / `generate_flutter_log.ps1`: Automated log generator utilities.

---

## 🛠️ Prerequisites & Setup

Ensure the following environments are installed on your machine:
1. **Node.js** (v18+ or v22+)
2. **Flutter SDK** (v3.22+ or v3.35+)
3. **Dart SDK** (included with Flutter)

---

## 🚀 Execution & Command Reference

### 1. Smart Contract Tests (Solidity / Hardhat)
To run the 25 smart contract automated tests using Hardhat:
```bash
# Navigate to the blockchain directory
cd digital-goods-blockchain

# Install dependencies
npm install

# Run the mocha test suite
npx hardhat test
```

### 2. Flutter Unit Tests (Dart)
To run the 17 core service unit tests:
```bash
# Navigate to the Flutter project directory
cd digitalgoods

# Resolve Flutter dependencies
flutter pub get

# Run the unit tests
flutter test test/digitalgoods_unit_test.dart
```

### 3. Running the Automated Log Generators (PowerShell)
To execute the test suites and automatically compile formal SQA evidence log files containing environment and execution info:
```powershell
# Generate Hardhat smart contract execution log
powershell -ExecutionPolicy Bypass -File .\test-results\generate_hardhat_log.ps1

# Generate Flutter unit test execution log
powershell -ExecutionPolicy Bypass -File .\test-results\generate_flutter_log.ps1
```
The logs will be generated and saved to `.\test-results\logs\`.
