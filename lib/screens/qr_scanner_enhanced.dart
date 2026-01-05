// FILE: lib/screens/qr_scanner_enhanced.dart
// =====================================================
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
import 'user_screens.dart'; // Import for navigation to details if needed
import 'shared_screens.dart';
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
      // Expected Format: asset://type/firebase_id/blockchain_id
      // Example: asset://land/abc123firebase/10
      // Example Pending: asset://land/abc123firebase/pending

      final parts = code.split('/');
      if (parts.length < 4) {
        throw Exception('Invalid QR code format. Expected asset://type/id/token_id');
      }

      final type = parts[1];
      final firebaseId = parts[2];
      final blockchainIdString = parts[3];

      // 1. FIX: Handle "pending" state gracefully
      if (blockchainIdString.toLowerCase() == 'pending' || blockchainIdString.toLowerCase() == 'null') {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.hourglass_empty, color: Colors.orange[700]),
                const SizedBox(width: 8),
                const Text("Pending Blockchain"),
              ],
            ),
            content: const Text(
              "This asset has been uploaded but is still waiting for blockchain confirmation (Mining).\n\n"
                  "Please try scanning again in a few minutes.",
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Optional: You could navigate to the firebase detail view here if you wanted
                    // Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: firebaseId)));
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
        throw Exception('Invalid Blockchain ID: $blockchainIdString');
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

      // 4. Fetch IPFS Data (if available)
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

      // 5. Show Success Dialog
      await showDialog(
        context: context,
        builder: (ctx) => VerificationResultDialog(
          type: type,
          firebaseId: firebaseId,
          blockchainId: blockchainId,
          blockchainData: blockchainData!,
          ipfsData: ipfsData,
        ),
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      // Resume scanning after processing is done (optional delay to prevent double-scan)
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

  const VerificationResultDialog({
    super.key,
    required this.type,
    required this.firebaseId,
    required this.blockchainId,
    required this.blockchainData,
    this.ipfsData,
  });

  @override
  Widget build(BuildContext context) {
    // Note: Some contracts return 'isVerified' as a boolean, others might not.
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
            _buildDetailRow('Owner', _shortenAddress(blockchainData['originalOwner']?.toString() ?? 'Unknown')),

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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            // Navigate to full details
            Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: firebaseId))
            );
          },
          child: const Text('View Full Details'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
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