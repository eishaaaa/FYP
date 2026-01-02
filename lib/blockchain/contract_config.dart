// lib/blockchain/contract_config.dart
class ContractConfig {
  static const String networkName = 'amoy';
  static const int chainId = 80002;

  // ✅ PUBLIC RPC (Stable)
  static const String rpcUrl = 'https://polygon-amoy.drpc.org';

  // RAW STRINGS
  static const String _rawElectronicsAddr = '0x4cd1E1FD136C959842d7FaBFc24E247A390Bd573';
  static const String _rawLandAddr = '0x1F60c3fB4cd2e69190dcf02256d310821694e5E1';

  // CLEAN GETTERS (Automatically removes invisible characters)
  static String get electronicsNFTAddress => _clean(_rawElectronicsAddr);
  static String get landNFTAddress => _clean(_rawLandAddr);

  // Helper to strip invisible characters
  static String _clean(String input) {
    return input.replaceAll(RegExp(r'[^0-9a-fA-Fx]'), '');
  }

  static String getExplorerUrl(String txHash) {
    return 'https://amoy.polygonscan.com/tx/$txHash';
  }

  static String getAddressUrl(String address) {
    return 'https://amoy.polygonscan.com/address/$address';
  }
}