
// lib/blockchain/contract_config.dart
// Auto-generated on 2025-12-25T16:45:11.840Z

class ContractConfig {
  static const String networkName = 'amoy';
  static const int chainId = 80002;
  static const String rpcUrl = 'https://rpc-amoy.polygon.technology';
  
  static const String electronicsNFTAddress = '0x4cd1E1FD136C959842d7FaBFc24E247A390Bd573';
  static const String landNFTAddress = '0x1F60c3fB4cd2e69190dcf02256d310821694e5E1';
  
  static String getExplorerUrl(String txHash) {
    return 'https://amoy.polygonscan.com/tx/\$txHash';
  }

  static String getAddressUrl(String address) {
    return 'https://amoy.polygonscan.com/address/\$address';
  }
}
