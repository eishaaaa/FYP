
// lib/blockchain/contract_config.dart
// Auto-generated on 2026-04-28T07:12:09.713Z

class ContractConfig {
  static const String networkName = 'amoy';
  static const int chainId = 80002;
  static const String rpcUrl = 'https://polygon-amoy.drpc.org';
  
  static const String electronicsNFTAddress = '0x1BE55F781F824d710FdF5A14cbb1C10799Ff39A1';
  static const String landNFTAddress = '0xdD683DaC3Fc6eC75F228c244eAC5e6FC1c80c241';
  
  static String getExplorerUrl(String txHash) {
    return 'https://amoy.polygonscan.com/tx/\$txHash';
  }

  static String getAddressUrl(String address) {
    return 'https://amoy.polygonscan.com/address/\$address';
  }
}
