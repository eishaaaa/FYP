// FILE: lib/screens/qr_scanner_enhanced.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
import 'user_screens.dart';
import 'shared_screens.dart';
import 'transfer_history_screen.dart';

class QRScannerEnhanced extends StatefulWidget {
  const QRScannerEnhanced({super.key});

  @override
  State<QRScannerEnhanced> createState() => _QRScannerEnhancedState();
}

class _QRScannerEnhancedState extends State<QRScannerEnhanced> {
  final _controller = MobileScannerController();
  final _blockchainService = BlockchainServiceEnhanced();
  final _ipfsService = IPFSService();

  bool _processing = false;

  Future<void> _handleQRCode(String code) async {
    if (_processing) return;
    setState(() => _processing = true);

    try {
      // Robust URI Parsing fixes the "double slash" bug
      // Expected Format: asset://type/firebase_id/blockchain_id
      final uri = Uri.parse(code);

      if (uri.scheme != 'asset') {
        throw Exception('Invalid QR type. Expected "asset://", got "$code"');
      }

      // FIX: Relaxed check to allow 2 segments (Old format) or 3 segments (New format)
      // pathSegments handles splitting automatically
      if (uri.pathSegments.length < 2) {
        throw Exception('Incomplete QR data. Expected at least 2 segments (Type/ID), got ${uri.pathSegments.length}');
      }

      final type = uri.pathSegments[0];
      final firebaseId = uri.pathSegments[1];

      // FIX: Handle missing 3rd segment gracefully
      final blockchainIdString = uri.pathSegments.length > 2
          ? uri.pathSegments[2]
          : 'pending';

      // 1. Handle "pending" state gracefully
      // This also catches old QR codes that didn't have a Token ID yet
      if (blockchainIdString.toLowerCase() == 'pending' || blockchainIdString.toLowerCase() == 'null') {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.hourglass_empty, color: Colors.orange[700]),
                const SizedBox(width: 8),
                const Text("Pending or Legacy Asset"),
              ],
            ),
            content: const Text(
              "This asset is either waiting for blockchain confirmation or is using an older QR format.\n\n"
                  "Please try regenerating the QR code if the asset is already minted.",
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Optional: Resume scanning immediately or wait
                  },
                  child: const Text("OK")
              )
            ],
          ),
        );
        return;
      }

      // 2. Parse ID after verifying it's not pending
      final blockchainId = int.tryParse(blockchainIdString);
      if (blockchainId == null) {
        throw Exception('Invalid Blockchain ID format: $blockchainIdString');
      }

      // 3. Fetch Data from Blockchain
      await _blockchainService.init();
      Map<String, dynamic>? blockchainData;

      if (type == 'electronics') {
        blockchainData = await _blockchainService.getDevice(blockchainId);
      } else if (type == 'land') {
        blockchainData = await _blockchainService.getLandProperty(blockchainId);
      }

      if (blockchainData == null) {
        throw Exception('Asset #$blockchainId not found on blockchain.');
      }

      // 4. Fetch Current Owner
      String? currentOwner;
      try {
        currentOwner = await _blockchainService.getOwnerOf(type, blockchainId);
      } catch (e) {
        debugPrint("Owner fetch error: $e");
      }

      // 5. Fetch IPFS Data (if available)
      final ipfsHash = blockchainData['ipfsMetadata'] ?? blockchainData['tokenURI'];
      Map<String, dynamic>? ipfsData;

      if (ipfsHash != null && ipfsHash.toString().isNotEmpty) {
        final hash = _ipfsService.extractHashFromUrl(ipfsHash);
        if (hash != null) {
          try {
            ipfsData = await _ipfsService.retrieveJSON(hash);
          } catch (e) {
            debugPrint("IPFS Fetch Error (Non-fatal): $e");
          }
        }
      }

      if (!mounted) return;

      // 6. Show Success Dialog
      await showDialog(
        context: context,
        builder: (ctx) => VerificationResultDialog(
          type: type,
          firebaseId: firebaseId,
          blockchainId: blockchainId,
          blockchainData: blockchainData!,
          ipfsData: ipfsData,
          currentOwner: currentOwner,
        ),
      );

    } catch (e) {
      debugPrint("Scan Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan Error: ${e.toString().replaceAll("Exception:", "")}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      // Delay slightly before allowing next scan to prevent double-trigger
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Asset QR')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.first.rawValue;
              if (code != null) _handleQRCode(code);
            },
          ),
          // Overlay Box Guide
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Align QR Code",
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          // Loading Indicator
          if (_processing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Verifying on blockchain...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class VerificationResultDialog extends StatelessWidget {
  final String type;
  final String firebaseId;
  final int blockchainId;
  final Map<String, dynamic> blockchainData;
  final Map<String, dynamic>? ipfsData;
  final String? currentOwner;

  const VerificationResultDialog({
    super.key,
    required this.type,
    required this.firebaseId,
    required this.blockchainId,
    required this.blockchainData,
    this.ipfsData,
    this.currentOwner,
  });

  @override
  Widget build(BuildContext context) {
    // Determine verification status
    final isVerified = blockchainData['isVerified'] == true;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isVerified ? Icons.verified : Icons.verified_outlined,
            color: isVerified ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 8),
          const Text('Asset Verified'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isVerified ? Colors.green[100] : Colors.blue[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isVerified ? Colors.green : Colors.blue),
              ),
              child: Text(
                isVerified ? '✓ OFFICIALLY VERIFIED' : '✓ AUTHENTIC ASSET',
                style: TextStyle(
                    color: isVerified ? Colors.green[900] : Colors.blue[900],
                    fontWeight: FontWeight.bold
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),

            const Text('Blockchain Record:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildDetailRow('Token ID', '#$blockchainId'),
            _buildDetailRow('Original Minter', _shortenAddress(blockchainData['originalOwner']?.toString() ?? 'Unknown')),

            if (currentOwner != null)
              _buildDetailRow('Current Owner', _shortenAddress(currentOwner!), isHighlight: true),

            if (type == 'electronics') ...[
              _buildDetailRow('Brand', blockchainData['brand'] ?? '-'),
              _buildDetailRow('Model', blockchainData['model'] ?? '-'),
              _buildDetailRow('Serial', blockchainData['serialNumber'] ?? '-'),
            ] else ...[
              _buildDetailRow('Location', blockchainData['location'] ?? '-'),
              _buildDetailRow('City', blockchainData['city'] ?? '-'),
              _buildDetailRow('Area', '${blockchainData['totalArea']} ${blockchainData['areaUnit']}'),
            ],

            const SizedBox(height: 12),
            const Divider(),

            if (ipfsData != null) ...[
              const Text('Digital Verification:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.cloud_done, color: Colors.purple, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Metadata & Documents verified on IPFS')),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            // Navigate to History Screen
            Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TransferHistoryScreen(
                  assetId: firebaseId,
                  assetTitle: blockchainData['brand'] ?? blockchainData['location'] ?? 'Asset',
                ))
            );
          },
          icon: const Icon(Icons.history),
          label: const Text('History'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                color: isHighlight ? Colors.green[700] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}