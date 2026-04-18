import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../blockchain/ipfs_service.dart';

// ─────────────────────────────────────────────────────────────
//  DATA MODEL
// ─────────────────────────────────────────────────────────────
class StolenReport {
  final String id;
  final String userId;
  final String assetId;
  final String assetType; // 'electronics' | 'land'
  final String assetName;
  final String description;
  final String? docIpfsHash;
  final String? docFileName;
  final String status; // 'pending' | 'investigating' | 'resolved'
  final DateTime createdAt;
  final String walletAddress;

  StolenReport({
    required this.id,
    required this.userId,
    required this.assetId,
    required this.assetType,
    required this.assetName,
    required this.description,
    this.docIpfsHash,
    this.docFileName,
    required this.status,
    required this.createdAt,
    required this.walletAddress,
  });

  factory StolenReport.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return StolenReport(
      id: doc.id,
      userId: d['userId'] ?? '',
      assetId: d['assetId'] ?? '',
      assetType: d['assetType'] ?? 'electronics',
      assetName: d['assetName'] ?? 'Unknown Asset',
      description: d['description'] ?? '',
      docIpfsHash: d['docIpfsHash'],
      docFileName: d['docFileName'],
      status: d['status'] ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      walletAddress: d['walletAddress'] ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MAIN SCREEN  (tab controller: My Reports | Submit New)
// ─────────────────────────────────────────────────────────────
class StolenReportScreen extends StatefulWidget {
  const StolenReportScreen({Key? key}) : super(key: key);

  @override
  State<StolenReportScreen> createState() => _StolenReportScreenState();
}

class _StolenReportScreenState extends State<StolenReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text(
          'Stolen Report',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A3A8F),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'My Reports'),
            Tab(icon: Icon(Icons.report_problem_outlined), text: 'Submit New'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MyReportsTab(),
          _SubmitReportTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 1 – MY REPORTS
// ─────────────────────────────────────────────────────────────
class _MyReportsTab extends StatefulWidget {
  const _MyReportsTab({Key? key}) : super(key: key);

  @override
  State<_MyReportsTab> createState() => _MyReportsTabState();
}

class _MyReportsTabState extends State<_MyReportsTab>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;

  // Stream subscription — switches to fallback if index is missing
  StreamSubscription<QuerySnapshot>? _sub;
  List<StolenReport> _reports     = [];
  bool               _loading     = true;
  bool               _indexMissing = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    // Try ordered stream first (needs composite index).
    _sub = FirebaseFirestore.instance
        .collection('stolen_reports')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      _onData,
      onError: (e) {
        // Index not ready yet — switch to unordered and sort client-side.
        debugPrint('Index missing, using fallback: $e');
        _sub?.cancel();
        if (mounted) setState(() => _indexMissing = true);
        _sub = FirebaseFirestore.instance
            .collection('stolen_reports')
            .where('userId', isEqualTo: uid)
            .snapshots()
            .listen(_onData, onError: (e2) {
          debugPrint('Fallback stream error: $e2');
          if (mounted) setState(() => _loading = false);
        });
      },
    );
  }

  void _onData(QuerySnapshot snap) {
    if (!mounted) return;
    var reports = snap.docs.map(StolenReport.fromFirestore).toList();
    // Sort client-side when index is missing
    if (_indexMissing) {
      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    setState(() {
      _reports = reports;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'investigating':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      default:
        return const Color(0xFF1A3A8F);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'investigating':
        return Icons.manage_search;
      case 'resolved':
        return Icons.check_circle_outline;
      default:
        return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF1A3A8F)));
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No stolen reports yet.',
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 8),
            Text('Use the "Submit New" tab to file a complaint.',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) {
        final r = _reports[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showReportDetail(context, r),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                          const Color(0xFF1A3A8F).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          r.assetType == 'land'
                              ? '🏕 Land'
                              : '📱 Electronics',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1A3A8F),
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(r.status).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_statusIcon(r.status),
                                size: 13,
                                color: _statusColor(r.status)),
                            const SizedBox(width: 4),
                            Text(
                              r.status[0].toUpperCase() +
                                  r.status.substring(1),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _statusColor(r.status),
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(r.assetName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E))),
                  const SizedBox(height: 4),
                  Text(r.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                      TextStyle(fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 13, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MMM dd, yyyy – HH:mm')
                            .format(r.createdAt),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500]),
                      ),
                      const Spacer(),
                      if (r.docIpfsHash != null)
                        Row(
                          children: [
                            Icon(Icons.attach_file,
                                size: 13, color: Colors.green[600]),
                            const SizedBox(width: 3),
                            Text('Doc attached',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[600])),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showReportDetail(BuildContext context, StolenReport r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportDetailSheet(report: r),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  REPORT DETAIL BOTTOM SHEET
// ─────────────────────────────────────────────────────────────
class _ReportDetailSheet extends StatelessWidget {
  final StolenReport report;
  const _ReportDetailSheet({required this.report});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Report Details',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E))),
            const SizedBox(height: 20),
            _detailRow(Icons.inventory_2_outlined, 'Asset', report.assetName),
            _detailRow(Icons.category_outlined, 'Type',
                report.assetType == 'land' ? 'Land Fraction' : 'Electronics'),
            _detailRow(Icons.tag, 'Asset ID', report.assetId),
            _detailRow(Icons.account_balance_wallet_outlined, 'Wallet',
                '${report.walletAddress.substring(0, 8)}...${report.walletAddress.substring(report.walletAddress.length - 6)}'),
            _detailRow(Icons.calendar_today, 'Filed On',
                DateFormat('MMM dd, yyyy – HH:mm').format(report.createdAt)),
            _detailRow(
                Icons.info_outline,
                'Status',
                report.status[0].toUpperCase() + report.status.substring(1)),
            const Divider(height: 28),
            const Text('Description',
                style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(report.description,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            ),
            if (report.docIpfsHash != null) ...[
              const SizedBox(height: 20),
              const Text('Attached Document',
                  style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.red[400]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(report.docFileName ?? 'Document',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            'IPFS: ${report.docIpfsHash!.substring(0, 16)}...',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.verified, color: Colors.green[600], size: 20),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1A3A8F)),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 2 – SUBMIT NEW REPORT
// ─────────────────────────────────────────────────────────────
class _SubmitReportTab extends StatefulWidget {
  const _SubmitReportTab({Key? key}) : super(key: key);

  @override
  State<_SubmitReportTab> createState() => _SubmitReportTabState();
}

class _SubmitReportTabState extends State<_SubmitReportTab>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;

  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();

  // Asset selection
  List<Map<String, dynamic>> _userAssets = [];
  Map<String, dynamic>? _selectedAsset;
  bool _loadingAssets = true;

  // Document
  PlatformFile? _pickedFile;
  bool _uploadingDoc = false;

  // Submit state
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadUserAssets();
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  // ── Load assets owned by current user ──────────────────────
  // Mirrors MyAssetsScreen exactly:
  //   collection : 'assets'
  //   ownership  : 'ownerId' OR 'ownerUid'  (both fields in use)
  //   name field : 'title'
  //   type field : 'category'  ('land' | 'electronics')
  //   token field: 'blockchainTokenId'
  Future<void> _loadUserAssets() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Two parallel queries — same pattern as MyAssetsScreen
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('assets')
            .where('ownerId', isEqualTo: uid)
            .get(),
        FirebaseFirestore.instance
            .collection('assets')
            .where('ownerUid', isEqualTo: uid)
            .get(),
      ]);

      // Merge & deduplicate by document ID
      final seen  = <String>{};
      final assets = <Map<String, dynamic>>[];

      for (final snap in results) {
        for (final doc in snap.docs) {
          if (!seen.add(doc.id)) continue; // already added
          final data = doc.data();
          assets.add({
            'id'     : doc.id,
            'name'   : (data['title'] as String?)
                ?? 'Asset #${doc.id.substring(0, 6)}',
            'type'   : (data['category'] as String?) ?? 'electronics',
            'tokenId': data['blockchainTokenId']?.toString() ?? '',
          });
        }
      }

      if (mounted) {
        setState(() {
          _userAssets    = assets;
          _loadingAssets = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading assets: $e');
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  // ── Pick document ───────────────────────────────────────────
  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  // ── Submit report ───────────────────────────────────────────
  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAsset == null) {
      _showSnack('Please select an asset.', isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _submitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      String? docHash;
      String? docName;

      // Upload document to IPFS if selected
      if (_pickedFile != null && _pickedFile!.bytes != null) {
        if (mounted) setState(() => _uploadingDoc = true);
        try {
          final result = await IPFSService().uploadFile(
            fileBytes: _pickedFile!.bytes!,
            fileName: _pickedFile!.name,
            metadata: {'type': 'stolen_report_document'},
          );
          if (!result.success || result.ipfsHash == null) {
            throw Exception(result.error ?? 'Unknown upload error');
          }
          docHash = result.ipfsHash;
          docName = _pickedFile!.name;
        } catch (e) {
          _showSnack('Document upload failed: $e', isError: true);
          setState(() {
            _submitting = false;
            _uploadingDoc = false;
          });
          return;
        }
        if (mounted) setState(() => _uploadingDoc = false);
      }

      // Get wallet address from Firestore
      String walletAddress = '';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        walletAddress = userDoc.data()?['walletAddress'] ?? '';
      } catch (_) {}

      // Save to Firestore
      await FirebaseFirestore.instance.collection('stolen_reports').add({
        'userId': user.uid,
        'assetId': _selectedAsset!['id'],
        'assetType': _selectedAsset!['type'],
        'assetName': _selectedAsset!['name'],
        'tokenId': _selectedAsset!['tokenId'],
        'description': _descController.text.trim(),
        'docIpfsHash': docHash,
        'docFileName': docName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'walletAddress': walletAddress,
      });

      if (mounted) {
        _showSnack('Stolen report submitted successfully!');
        // Reset form
        setState(() {
          _selectedAsset = null;
          _pickedFile = null;
        });
        _descController.clear();
      }
    } catch (e) {
      _showSnack('Error submitting report: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info banner ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You can only report assets that you currently own. '
                          'Attach your official police complaint document for faster processing.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.orange[800],
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Select Asset ──
            const _SectionLabel(icon: Icons.inventory_2_outlined, text: 'Select Stolen Asset'),
            const SizedBox(height: 10),
            _loadingAssets
                ? const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF1A3A8F)))
                : _userAssets.isEmpty
                ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.grey[400]),
                  const SizedBox(width: 10),
                  Text('You have no assets to report.',
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            )
                : DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedAsset,
              isExpanded: true, // forces the button to fill its width
              decoration: _inputDecoration('Choose your asset'),
              items: _userAssets.map((asset) {
                final emoji =
                asset['type'] == 'land' ? '🏕  ' : '📱  ';
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: asset,
                  child: Text(
                    '$emoji${asset['name']}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                );
              }).toList(),
              onChanged: (val) =>
                  setState(() => _selectedAsset = val),
              validator: (val) =>
              val == null ? 'Please select an asset' : null,
            ),

            const SizedBox(height: 24),

            // ── Description ──
            const _SectionLabel(
                icon: Icons.description_outlined, text: 'Incident Description'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descController,
              maxLines: 5,
              decoration: _inputDecoration(
                  'Describe the theft incident (when, where, how...)'),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Description is required';
                }
                if (val.trim().length < 20) {
                  return 'Please provide at least 20 characters';
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            // ── Police Document ──
            const _SectionLabel(
                icon: Icons.gavel_outlined,
                text: 'Police Complaint Document'),
            const SizedBox(height: 6),
            Text(
              'Optional but recommended — PDF, image, or Word doc',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickDocument,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _pickedFile != null
                      ? Colors.green[50]
                      : const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _pickedFile != null
                        ? Colors.green[300]!
                        : const Color(0xFF1A3A8F).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pickedFile != null
                          ? Icons.check_circle
                          : Icons.upload_file,
                      color: _pickedFile != null
                          ? Colors.green[600]
                          : const Color(0xFF1A3A8F),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _pickedFile != null
                          ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pickedFile!.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB • Tap to change',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      )
                          : Text(
                        'Tap to attach police complaint document',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13),
                      ),
                    ),
                    if (_pickedFile != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.grey[500],
                        onPressed: () => setState(() => _pickedFile = null),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 36),

            // ── Submit button ──
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: (_submitting || _loadingAssets) ? null : _submitReport,
                icon: _submitting
                    ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined),
                label: Text(
                  _uploadingDoc
                      ? 'Uploading Document...'
                      : _submitting
                      ? 'Submitting...'
                      : 'Submit Stolen Report',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A3A8F),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
        const BorderSide(color: Color(0xFF1A3A8F), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HELPER WIDGET
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF1A3A8F)),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E)),
        ),
      ],
    );
  }
}