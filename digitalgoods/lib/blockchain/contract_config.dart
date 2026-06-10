// lib/blockchain/contract_config.dart
class ContractConfig {
  static const String networkName = 'amoy';
  static const int chainId = 80002;


  static const String rpcUrl = 'https://polygon-amoy.drpc.org';

  static const String _rawElectronicsAddr = '0x1799Bbec3d1FA0B549d5f37D848336244391c8a3';
  static const String _rawLandAddr = '0x6ed49d1af167f6c5d4dCCbF83c8Bbf6D0482AbB5';

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