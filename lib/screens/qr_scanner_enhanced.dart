// FILE: lib/screens/qr_scanner_enhanced.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
import '../theme.dart';
// import 'user_screens.dart';
// import 'shared_screens.dart';
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
      // Robust manual parsing for custom asset:// scheme.
      // Uri.parse() treats the first segment of asset://type/id/token as the
      // authority/host, yielding only 2 pathSegments instead of 3.
      // Fix: strip the prefix and split the remaining path ourselves.
      const prefix = 'asset://';
      if (!code.startsWith(prefix)) {
        throw Exception('Invalid QR type. Expected "asset://", got "$code"');
      }

      final segments = code.substring(prefix.length).split('/');
      if (segments.length < 3) {
        throw Exception('Incomplete QR data. Expected 3 segments, got ${segments.length}');
      }

      final type = segments[0];
      final firebaseId = segments[1];
      final blockchainIdString = segments[2];

      // 1. Firebase Fallback: QR may have been printed before Admin verification.
      //    When the QR carries "pending" or "null", do a one-time live Firestore
      //    fetch to see whether the Admin has since minted a blockchainTokenId.
      int? resolvedBlockchainId;

      if (blockchainIdString.toLowerCase() == 'pending' ||
          blockchainIdString.toLowerCase() == 'null') {
        debugPrint('QR has pending ID – fetching live Firestore doc for $firebaseId ...');
        try {
          final docSnapshot = await FirebaseFirestore.instance
              .collection('assets')
              .doc(firebaseId)
              .get();

          if (docSnapshot.exists) {
            final liveData = docSnapshot.data();
            final liveTokenId = liveData?['blockchainTokenId'];
            if (liveTokenId != null) {
              // Admin has verified the asset since the QR was printed.
              resolvedBlockchainId = (liveTokenId is int)
                  ? liveTokenId
                  : int.tryParse(liveTokenId.toString());
            }
          }
        } catch (e) {
          debugPrint('Firestore fallback fetch error (non-fatal): $e');
        }

        // If still no real ID after the live fetch, show the Pending dialog.
        if (resolvedBlockchainId == null) {
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  const Flexible(child: Text("Pending Blockchain")),
                ],
              ),
              content: const Text(
                "This asset has been uploaded but is still waiting for "
                    "blockchain confirmation (Mining).\n\n"
                    "Please try scanning again in a few minutes.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK"),
                )
              ],
            ),
          );
          return;
        }
      }

      // 2. Resolve the final blockchainId (from QR or from Firestore fallback)
      final blockchainId = resolvedBlockchainId ?? int.tryParse(blockchainIdString);
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

      // --- SECURITY & SELF-HEALING ---
      bool isHealthy = await _blockchainService.verifyAndHealAsset(
        type: type,
        blockchainId: blockchainId,
        firestoreDocId: firebaseId,
        firestore: FirebaseFirestore.instance,
      );
      if (!isHealthy && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Security Check: Syncing secure data from blockchain...'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      // -------------------------------

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
            content: Text('Scan Error: $e'),
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
      appBar: AppBar(
        title: Text('Scan Asset QR', style: AppTheme.heading(18, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
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
              child: Center(
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppTheme.primaryStart),
                        const SizedBox(height: 20),
                        Text('Verifying on blockchain...', style: AppTheme.body(15, weight: FontWeight.w600)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Icon(
            isVerified ? Icons.verified : Icons.verified_outlined,
            color: isVerified ? Colors.green : AppTheme.primaryStart,
          ),
          const SizedBox(width: 10),
          Text('Asset Verified', style: AppTheme.heading(20)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isVerified ? Colors.green[50] : AppTheme.primaryStart.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isVerified ? Colors.green : AppTheme.primaryStart.withOpacity(0.3)),
              ),
              child: Text(
                isVerified ? '✓ OFFICIALLY VERIFIED' : '✓ AUTHENTIC ASSET',
                style: AppTheme.body(12,
                    weight: FontWeight.bold,
                    color: isVerified ? Colors.green[900]! : AppTheme.primaryStartDark),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 32),
            Text('Blockchain Record', style: AppTheme.heading(14)),
            const SizedBox(height: 8),
            _buildDetailRow('Token ID', '#$blockchainId'),
            _buildDetailRow('Original Minter', _shortenAddress(blockchainData['originalOwner']?.toString() ?? 'Unknown')),

            if (currentOwner != null)
              _buildDetailRow('Current Owner', _shortenAddress(currentOwner!), isHighlight: true),

            if (type == 'electronics') ...[
              _buildDetailRow('Brand', blockchainData['brand'] ?? '-'),
              _buildDetailRow('Model', blockchainData['model'] ?? '-'),
              _buildDetailRow('Serial', blockchainData['serialNumber'] ?? '-'),
              const SizedBox(height: 12),
              const Text('Verified Provenance Path:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 8),
              _buildProvenanceTimeline(blockchainData['status'] ?? 0, blockchainData['ownerCount'] ?? 0),
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
              ),),
            );
          },
          icon: const Icon(Icons.history, color: AppTheme.primaryStart),
          label: Text('History', style: AppTheme.body(14, color: AppTheme.primaryStart, weight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: AppTheme.body(14, color: AppTheme.textSecondary)),
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

  Widget _buildProvenanceTimeline(int status, int ownerCount) {
    // status: 0 = InTransit, 1 = InStock, 2 = Sold
    List<Widget> steps = [];

    // Step 1: Manufacturer
    steps.add(_buildTimelineStep('Manufacturer', 'Minted & Sealed', true));

    // Step 2: Logistics / Vendor
    bool isAtVendor = status >= 0; // Always true if minted
    steps.add(_buildTimelineStep('Vendor', 'In Transit (Sealed)', isAtVendor));

    // Step 3: Retailer
    bool isAtRetailer = status >= 1;
    steps.add(_buildTimelineStep('Retailer', 'In Stock (Sealed)', isAtRetailer));

    // Step 4: Customer
    bool isSold = status == 2;
    String customerLabel = isSold ? (ownerCount <= 1 ? '1st Owner' : 'Owner #$ownerCount') : 'Unsold';
    steps.add(_buildTimelineStep('Customer', customerLabel, isSold, isLast: true));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: steps,
    );
  }

  Widget _buildTimelineStep(String title, String subtitle, bool isCompleted, {bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isCompleted ? Colors.green : Colors.grey,
              size: 20,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: isCompleted ? Colors.green : Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isCompleted ? Colors.black87 : Colors.grey)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (!isLast) const SizedBox(height: 12),
          ],
        ),
      ],
    );
  }
}