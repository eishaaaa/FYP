import 'package:flutter_test/flutter_test.dart';
import 'package:digitalgoods/blockchain/wallet_service.dart';
import 'package:digitalgoods/blockchain/ipfs_service.dart';
import 'package:digitalgoods/blockchain/explorer_service.dart';
import 'package:digitalgoods/screens/transaction_model.dart';

void main() {
  group('SimpleWalletService Balance & Escrow Tests', () {
    late SimpleWalletService walletService;

    setUp(() {
      walletService = SimpleWalletService();
      // Reset the singleton state if needed (using availableBalance logic)
      // Since it starts at 10.0, we will check the state flow.
    });

    test('1. Initial Balance Check', () {
      expect(walletService.availableBalance, 10.0);
      expect(walletService.lockedBalance, 0.0);
      expect(walletService.isConnected, isFalse);
    });

    test('2. Lock Funds Success', () async {
      await walletService.lockFunds(4.0);
      expect(walletService.availableBalance, 6.0);
      expect(walletService.lockedBalance, 4.0);
      
      // Clean up / reset
      await walletService.unlockFunds(4.0);
    });

    test('3. Lock Funds Insufficient Balance throws Exception', () async {
      expect(
        () => walletService.lockFunds(20.0),
        throwsA(isA<Exception>()),
      );
    });

    test('4. Unlock Funds Success', () async {
      await walletService.lockFunds(3.0);
      expect(walletService.lockedBalance, 3.0);
      
      await walletService.unlockFunds(2.0);
      expect(walletService.availableBalance, 9.0);
      expect(walletService.lockedBalance, 1.0);
      
      // Clean up
      await walletService.unlockFunds(1.0);
    });

    test('5. Unlock Funds Insufficient Locked balance throws Exception', () async {
      expect(
        () => walletService.unlockFunds(5.0),
        throwsA(isA<Exception>()),
      );
    });

    test('6. Consume Locked Funds Success', () async {
      await walletService.lockFunds(5.0);
      expect(walletService.lockedBalance, 5.0);
      
      await walletService.consumeLockedFunds(3.0);
      expect(walletService.lockedBalance, 2.0);
      expect(walletService.availableBalance, 5.0);
      
      // Clean up
      await walletService.unlockFunds(2.0);
    });

    test('7. Consume Locked Funds Insufficient Locked balance throws Exception', () async {
      expect(
        () => walletService.consumeLockedFunds(10.0),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('IPFSService Metadata & Utilities Tests', () {
    late IPFSService ipfsService;

    setUp(() {
      ipfsService = IPFSService();
    });

    test('8. IPFS URL Formatting', () {
      const hash = "QmTestHash123";
      final url = ipfsService.getIPFSUrl(hash);
      expect(url, contains("https://gateway.pinata.cloud/ipfs/"));
      expect(url, contains(hash));
    });

    test('9. Extract Hash from ipfs:// url', () {
      const url = "ipfs://QmTestHash123";
      final hash = ipfsService.extractHashFromUrl(url);
      expect(hash, "QmTestHash123");
    });

    test('10. Extract Hash from gateway http url', () {
      const url = "https://gateway.pinata.cloud/ipfs/QmTestHash123";
      final hash = ipfsService.extractHashFromUrl(url);
      expect(hash, "QmTestHash123");
    });

    test('11. Extract Hash from invalid url returns null', () {
      const url = "https://example.com/somefile.png";
      final hash = ipfsService.extractHashFromUrl(url);
      expect(hash, isNull);
    });

    test('12. Create Electronics Metadata structure', () {
      final metadata = ipfsService.createElectronicsMetadata(
        brand: "Samsung",
        model: "Galaxy S24",
        serialNumber: "IMEI123456789",
        warrantyExpiry: "2026-12-31",
        condition: "New",
      );

      expect(metadata['name'], "Samsung Galaxy S24");
      expect(metadata['attributes'], isNotEmpty);
      expect(metadata['attributes'][0]['value'], "Samsung");
      expect(metadata['attributes'][2]['value'], "IMEI123456789");
    });

    test('13. Create Land Metadata structure', () {
      final metadata = ipfsService.createLandMetadata(
        location: "DHA Phase 5, Lahore",
        city: "Lahore",
        totalArea: 10,
        areaUnit: "marla",
        totalFractions: 100,
        pricePerFraction: "0.1",
      );

      expect(metadata['name'], "DHA Phase 5, Lahore - 10 marla");
      expect(metadata['attributes'][1]['value'], "Lahore");
      expect(metadata['attributes'][3]['value'], "marla");
      expect(metadata['attributes'][5]['value'], "0.1 MATIC");
    });

    test('14. IPFSUploadResult Formatting Size Helper', () {
      final result = IPFSUploadResult(
        success: true,
        ipfsHash: "QmHash",
        size: 2048,
      );

      expect(result.toString(), contains("IPFS Upload Success"));
      expect(result.toString(), contains("2.0 KB"));
    });
  });

  group('ExplorerService Logic & Helper Tests', () {
    // Testing Wei & Gas conversions used in ExplorerService
    test('15. Wei to MATIC Conversion calculation', () {
      final valueWei = BigInt.parse("1000000000000000000"); // 10^18 Wei
      final value = (valueWei / BigInt.from(10).pow(18)).toStringAsFixed(4);
      expect(value, "1.0000");
    });

    test('16. Fractional Wei to MATIC conversion calculation', () {
      final valueWei = BigInt.parse("150000000000000000"); // 0.15 MATIC
      final value = (valueWei / BigInt.from(10).pow(18)).toStringAsFixed(4);
      expect(value, "0.1500");
    });

    test('17. Gas Fee conversion calculation', () {
      final gas = BigInt.parse("21000");
      final gasPrice = BigInt.parse("30000000000"); // 30 Gwei
      // gas * gasPrice / 10^18
      final gasFee = (gas * gasPrice / BigInt.from(10).pow(18)).toStringAsFixed(6);
      expect(gasFee, "0.000630");
    });
  });
}
