// FILE 1: lib/screens/qr_scanner_enhanced.dart
// =====================================================
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';

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
      // Parse: asset://type/firebase_id/blockchain_id
      final parts = code.split('/');
      if (parts.length < 4) {
        throw Exception('Invalid QR code format');
      }

      final type = parts[1];
      final firebaseId = parts[2];
      final blockchainId = int.tryParse(parts[3]);

      if (blockchainId == null) {
        throw Exception('No blockchain ID found');
      }

      await _blockchainService.init();

      Map<String, dynamic>? blockchainData;

      if (type == 'electronics') {
        blockchainData = await _blockchainService.getDevice(blockchainId);
      } else if (type == 'land') {
        blockchainData = await _blockchainService.getLandProperty(blockchainId);
      }

      if (blockchainData == null) {
        throw Exception('Asset not found on blockchain');
      }

      final ipfsHash = blockchainData['ipfsMetadata'] ?? blockchainData['tokenURI'];
      Map<String, dynamic>? ipfsData;

      if (ipfsHash != null && ipfsHash.isNotEmpty) {
        final hash = _ipfsService.extractHashFromUrl(ipfsHash);
        if (hash != null) {
          ipfsData = await _ipfsService.retrieveJSON(hash);
        }
      }

      if (!mounted) return;

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
            content: Text('Verification failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
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
    final isVerified = blockchainData['isVerified'] ?? false;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isVerified ? Icons.verified : Icons.warning,
            color: isVerified ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          const Text('Verification Result'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isVerified ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isVerified ? '✓ VERIFIED' : '⚠ PENDING',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),

            const Text('Blockchain Details:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildDetailRow('Token ID', blockchainId.toString()),
            _buildDetailRow('Owner', _shortenAddress(blockchainData['originalOwner'])),

            if (type == 'electronics') ...[
              _buildDetailRow('Brand', blockchainData['brand']),
              _buildDetailRow('Model', blockchainData['model']),
              _buildDetailRow('Serial', blockchainData['serialNumber']),
            ] else ...[
              _buildDetailRow('Location', blockchainData['location']),
              _buildDetailRow('City', blockchainData['city']),
              _buildDetailRow('Area', '${blockchainData['totalArea']} ${blockchainData['areaUnit']}'),
            ],

            const SizedBox(height: 12),
            const Divider(),

            if (ipfsData != null) ...[
              const Text('Document Verification:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Documents verified on IPFS')),
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
            // Navigate to asset detail with firebaseId
          },
          child: const Text('View Details'),
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
              style: const TextStyle(color: Colors.grey),
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