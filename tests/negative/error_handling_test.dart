// tests/negative/error_handling_test.dart
import 'package:flutter_test/flutter_test.dart';

// Simple validation functions (these should exist in your actual code)
class ValidationHelpers {
  static void validatePurchaseAmount(dynamic amount) {
    if (amount == null || amount <= 0) {
      throw ArgumentError('Purchase amount must be greater than 0');
    }
  }

  static void validateFractionPercentage(dynamic percentage) {
    if (percentage == null || percentage < 0 || percentage > 100) {
      throw ArgumentError('Fraction percentage must be between 0 and 100');
    }
  }

  static void validateWalletAddress(String? address) {
    if (address == null || address.isEmpty) {
      throw ArgumentError('Wallet address cannot be empty');
    }
    if (!address.startsWith('0x') || address.length != 42) {
      throw ArgumentError('Invalid Ethereum wallet address format');
    }
  }

  static void validateEmail(String? email) {
    if (email == null || email.isEmpty) {
      throw ArgumentError('Email cannot be empty');
    }
    if (!email.contains('@') || !email.contains('.')) {
      throw ArgumentError('Invalid email format');
    }
  }

  static void validateFractionQuantity(dynamic quantity) {
    if (quantity == null || quantity < 1) {
      throw ArgumentError('Fraction quantity must be at least 1');
    }
  }
}

void main() {
  group('❌ NEGATIVE TESTING - Error Handling & Edge Cases', () {

    // Test Group 1: Purchase Amount Validation
    group('Purchase Amount Tests', () {
      test('Test 1: Reject 0 MATIC purchase', () {
        expect(
              () => ValidationHelpers.validatePurchaseAmount(0),
          throwsArgumentError,
        );
      });

      test('Test 2: Reject negative purchase amount', () {
        expect(
              () => ValidationHelpers.validatePurchaseAmount(-100),
          throwsArgumentError,
        );
      });

      test('Test 3: Reject null purchase amount', () {
        expect(
              () => ValidationHelpers.validatePurchaseAmount(null),
          throwsArgumentError,
        );
      });

      test('Test 4: Accept valid positive amount', () {
        expect(
              () => ValidationHelpers.validatePurchaseAmount(50.5),
          returnsNormally,
        );
      });
    });

    // Test Group 2: Fraction Percentage Validation
    group('Fraction Percentage Tests', () {
      test('Test 5: Reject negative fraction percentage', () {
        expect(
              () => ValidationHelpers.validateFractionPercentage(-5),
          throwsArgumentError,
        );
      });

      test('Test 6: Reject percentage > 100', () {
        expect(
              () => ValidationHelpers.validateFractionPercentage(150),
          throwsArgumentError,
        );
      });

      test('Test 7: Accept boundary value 0%', () {
        expect(
              () => ValidationHelpers.validateFractionPercentage(0),
          returnsNormally,
        );
      });

      test('Test 8: Accept boundary value 100%', () {
        expect(
              () => ValidationHelpers.validateFractionPercentage(100),
          returnsNormally,
        );
      });
    });

    // Test Group 3: Wallet Address Validation
    group('Wallet Address Tests', () {
      test('Test 9: Reject empty wallet address', () {
        expect(
              () => ValidationHelpers.validateWalletAddress(''),
          throwsArgumentError,
        );
      });

      test('Test 10: Reject null wallet address', () {
        expect(
              () => ValidationHelpers.validateWalletAddress(null),
          throwsArgumentError,
        );
      });

      test('Test 11: Reject address not starting with 0x', () {
        expect(
              () => ValidationHelpers.validateWalletAddress('1234567890abcdef'),
          throwsArgumentError,
        );
      });

      test('Test 12: Reject address with wrong length', () {
        expect(
              () => ValidationHelpers.validateWalletAddress('0x123'),
          throwsArgumentError,
        );
      });

      test('Test 13: Accept valid Ethereum address', () {
        expect(
              () => ValidationHelpers.validateWalletAddress('0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb'),
          returnsNormally,
        );
      });
    });

    // Test Group 4: Email Validation
    group('Email Validation Tests', () {
      test('Test 14: Reject empty email', () {
        expect(
              () => ValidationHelpers.validateEmail(''),
          throwsArgumentError,
        );
      });

      test('Test 15: Reject null email', () {
        expect(
              () => ValidationHelpers.validateEmail(null),
          throwsArgumentError,
        );
      });

      test('Test 16: Reject email without @', () {
        expect(
              () => ValidationHelpers.validateEmail('notanemail.com'),
          throwsArgumentError,
        );
      });

      test('Test 17: Reject email without domain', () {
        expect(
              () => ValidationHelpers.validateEmail('user@'),
          throwsArgumentError,
        );
      });

      test('Test 18: Accept valid email format', () {
        expect(
              () => ValidationHelpers.validateEmail('user@example.com'),
          returnsNormally,
        );
      });
    });

    // Test Group 5: Fraction Quantity Validation
    group('Fraction Quantity Tests', () {
      test('Test 19: Reject 0 quantity', () {
        expect(
              () => ValidationHelpers.validateFractionQuantity(0),
          throwsArgumentError,
        );
      });

      test('Test 20: Reject negative quantity', () {
        expect(
              () => ValidationHelpers.validateFractionQuantity(-10),
          throwsArgumentError,
        );
      });

      test('Test 21: Accept minimum quantity (1)', () {
        expect(
              () => ValidationHelpers.validateFractionQuantity(1),
          returnsNormally,
        );
      });

      test('Test 22: Accept large quantity', () {
        expect(
              () => ValidationHelpers.validateFractionQuantity(1000),
          returnsNormally,
        );
      });
    });

  });
}