import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../blockchain/ipfs_service.dart';
import '../theme.dart';

// ── THEME CONSTANTS ─────────────────────────────────────────────
const _kPrimary     = AppTheme.primaryStart;
const _kPrimaryDark = AppTheme.primaryEnd;
const _kAccent      = AppTheme.accent;
const _kBg          = AppTheme.background;
const _kCard        = Colors.white;

// ─────────────────────────────────────────────────────────────
//  DATA MODEL  (land removed – electronics only)
// ─────────────────────────────────────────────────────────────
class StolenReport {
  final String  id;
  final String  userId;
  final String  assetId;
  final String  assetType;   // always 'electronics'
  final String  assetName;
  final String  description;
  final String? docIpfsHash;
  final String? docFileName;
  final String  status;      // 'pending' | 'investigating' | 'resolved'
  final DateTime createdAt;
  final String  walletAddress;
  final String? imei;
  final String? serialNumber;
  final String? deviceCategory; // 'phone'|'laptop'|'tablet'|'watch'|'other'
  final String? assetImageUrl;  // optional photo of the device

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
    this.imei,
    this.serialNumber,
    this.deviceCategory,
    this.assetImageUrl,
  });

  factory StolenReport.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return StolenReport(
      id             : doc.id,
      userId         : d['userId']         ?? '',
      assetId        : d['assetId']        ?? '',
      assetType      : 'electronics',
      assetName      : d['assetName']      ?? 'Unknown Device',
      description    : d['description']    ?? '',
      docIpfsHash    : d['docIpfsHash'],
      docFileName    : d['docFileName'],
      status         : d['status']         ?? 'pending',
      createdAt      : (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      walletAddress  : d['walletAddress']  ?? '',
      imei           : d['imei'],
      serialNumber   : d['serialNumber'],
      deviceCategory : d['deviceCategory'],
      assetImageUrl  : d['assetImageUrl'] ?? d['imageUrl'],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MAIN SCREEN
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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text('Stolen Report', style: AppTheme.heading(20, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppTheme.primaryStart,
              unselectedLabelColor: Colors.white70,
              labelStyle: AppTheme.heading(11),
              unselectedLabelStyle: AppTheme.body(11),
              tabs: const [
                Tab(icon: Icon(Icons.list_alt,              size: 18), text: 'My Reports'),
                Tab(icon: Icon(Icons.public,                size: 18), text: 'All Reports'),
                Tab(icon: Icon(Icons.report_problem_outlined, size: 18), text: 'Submit New'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _MyReportsTab(),
          _AllReportsTab(),
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

  StreamSubscription<QuerySnapshot>? _sub;
  List<StolenReport> _reports      = [];
  bool               _loading      = true;
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
    _sub = FirebaseFirestore.instance
        .collection('stolen_reports')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(_onData, onError: (e) {
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
    });
  }

  void _onData(QuerySnapshot snap) {
    if (!mounted) return;
    var reports = snap.docs.map(StolenReport.fromFirestore).toList();
    if (_indexMissing) reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() {
      _reports = reports;
      _loading  = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'investigating': return Colors.orange;
      case 'resolved':      return Colors.green;
      default:              return _kPrimary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'investigating': return Icons.manage_search;
      case 'resolved':      return Icons.check_circle_outline;
      default:              return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kPrimary));
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color        : _kPrimary.withOpacity(0.08),
                shape        : BoxShape.circle,
              ),
              child: const Icon(Icons.devices_outlined, size: 56, color: _kPrimary),
            ),
            const SizedBox(height: 20),
            Text('No stolen reports yet.',
                style: AppTheme.heading(16, color: _kPrimaryDark)),
            const SizedBox(height: 8),
            Text('Use the "Submit New" tab to file a complaint.',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) {
        final r = _reports[i];
        return _ElectronicsReportCard(
          report      : r,
          statusColor : _statusColor(r.status),
          statusIcon  : _statusIcon(r.status),
          onTap       : () => _showReportDetail(context, r),
          isOwn       : true,
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
//  REUSABLE ELECTRONICS REPORT CARD
// ─────────────────────────────────────────────────────────────
class _ElectronicsReportCard extends StatelessWidget {
  final StolenReport report;
  final Color        statusColor;
  final IconData     statusIcon;
  final VoidCallback onTap;
  final bool         isOwn;

  const _ElectronicsReportCard({
    required this.report,
    required this.statusColor,
    required this.statusIcon,
    required this.onTap,
    this.isOwn = false,
  });

  IconData get _deviceIcon {
    switch (report.deviceCategory) {
      case 'laptop': return Icons.laptop_outlined;
      case 'tablet': return Icons.tablet_outlined;
      case 'watch':  return Icons.watch_outlined;
      default:       return Icons.smartphone_outlined;
    }
  }

  // Gradient colours for placeholder image panel
  List<Color> get _placeholderGradient {
    switch (report.deviceCategory) {
      case 'laptop': return [const Color(0xFF1565C0), const Color(0xFF1976D2)];
      case 'tablet': return [const Color(0xFF00695C), const Color(0xFF00897B)];
      case 'watch':  return [const Color(0xFF4527A0), const Color(0xFF5E35B1)];
      default:       return [_kPrimaryDark, _kPrimary];
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = report.assetImageUrl != null && report.assetImageUrl!.isNotEmpty;

    return Card(
      margin    : const EdgeInsets.only(bottom: 14),
      shape     : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation : 2,
      shadowColor: _kPrimary.withOpacity(0.10),
      color     : _kCard,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Left image panel (like sample) ────────────────
              SizedBox(
                width: 100,
                child: hasImage
                    ? Image.network(
                  report.assetImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildPlaceholder(),
                  loadingBuilder: (ctx, child, prog) =>
                  prog == null ? child : _buildPlaceholder(),
                )
                    : _buildPlaceholder(),
              ),

              // ── Right content ──────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // Badge row  ──  "Your report"  +  Status
                      Row(
                        children: [
                          if (isOwn) ...[
                            _MiniChip(
                              label : 'Your report',
                              color : Colors.purple,
                            ),
                            const SizedBox(width: 6),
                          ],
                          _MiniChip(
                            label : report.status[0].toUpperCase() +
                                report.status.substring(1),
                            color : statusColor,
                            icon  : statusIcon,
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right,
                              size: 18, color: Colors.grey[350]),
                        ],
                      ),
                      const SizedBox(height: 7),

                      // Asset name
                      Text(
                        report.assetName,
                        style: AppTheme.heading(15, color: _kPrimaryDark),
                      ),
                      const SizedBox(height: 3),

                      // Description
                      Text(
                        report.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                      ),

                      // IMEI / Serial verify chips
                      if (report.imei != null || report.serialNumber != null) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 5, runSpacing: 4,
                          children: [
                            if (report.imei != null)
                              _VerifyChip(
                                  label: 'IMEI ✓',
                                  icon : Icons.verified_user_outlined),
                            if (report.serialNumber != null)
                              _VerifyChip(
                                  label: 'S/N ✓',
                                  icon : Icons.qr_code_scanner),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),

                      // Footer – date + doc
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 11, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM dd, yyyy').format(report.createdAt),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                          const Spacer(),
                          if (report.docIpfsHash != null) ...[
                            Icon(Icons.attach_file,
                                size: 12, color: Colors.green[600]),
                            const SizedBox(width: 2),
                            Text('Doc attached',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.green[600])),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),  // Row
        ),    // IntrinsicHeight
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _placeholderGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(_deviceIcon, color: Colors.white.withOpacity(0.85), size: 38),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MINI CHIP
// ─────────────────────────────────────────────────────────────
class _MiniChip extends StatelessWidget {
  final String  label;
  final Color   color;
  final IconData? icon;
  const _MiniChip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color        : color.withOpacity(0.10),
        borderRadius : BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  VERIFY CHIP  (IMEI / Serial)
// ─────────────────────────────────────────────────────────────
class _VerifyChip extends StatelessWidget {
  final String  label;
  final IconData icon;
  const _VerifyChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color        : Colors.teal.withOpacity(0.08),
        borderRadius : BorderRadius.circular(20),
        border       : Border.all(color: Colors.teal.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.teal[700]),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: Colors.teal[700], fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 2 – ALL REPORTS  (search + electronics filter)
// ─────────────────────────────────────────────────────────────
class _AllReportsTab extends StatefulWidget {
  const _AllReportsTab({Key? key}) : super(key: key);

  @override
  State<_AllReportsTab> createState() => _AllReportsTabState();
}

class _AllReportsTabState extends State<_AllReportsTab>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;

  StreamSubscription<QuerySnapshot>? _sub;
  List<StolenReport> _all      = [];
  List<StolenReport> _filtered = [];
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery     = '';
  String _filterStatus    = 'All';    // 'All'|'pending'|'investigating'|'resolved'
  String _filterCategory  = 'All';    // 'All'|'phone'|'laptop'|'tablet'|'watch'|'other'
  bool?  _filterHasImei   ;           // null=All, true=has, false=no
  bool?  _filterHasSerial ;

  @override
  void initState() {
    super.initState();
    _startListening();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
        _applyFilters();
      });
    });
  }

  void _startListening() {
    _sub = FirebaseFirestore.instance
        .collection('stolen_reports')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(_onData, onError: (_) {
      _sub?.cancel();
      _sub = FirebaseFirestore.instance
          .collection('stolen_reports')
          .snapshots()
          .listen((snap) {
        final reports = snap.docs.map(StolenReport.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _onDataSorted(reports);
      });
    });
  }

  void _onData(QuerySnapshot snap) {
    if (!mounted) return;
    _all = snap.docs.map(StolenReport.fromFirestore).toList();
    _applyFilters();
    setState(() => _loading = false);
  }

  void _onDataSorted(List<StolenReport> sorted) {
    if (!mounted) return;
    _all = sorted;
    _applyFilters();
    setState(() => _loading = false);
  }

  void _applyFilters() {
    _filtered = _all.where((r) {
      final matchSearch = _searchQuery.isEmpty ||
          r.assetName.toLowerCase().contains(_searchQuery) ||
          r.description.toLowerCase().contains(_searchQuery) ||
          (r.imei?.toLowerCase().contains(_searchQuery) ?? false) ||
          (r.serialNumber?.toLowerCase().contains(_searchQuery) ?? false);

      final matchStatus   = _filterStatus   == 'All' || r.status          == _filterStatus;
      final matchCategory = _filterCategory == 'All' || r.deviceCategory  == _filterCategory;
      final matchImei     = _filterHasImei  == null  || (_filterHasImei == true ? r.imei != null : r.imei == null);
      final matchSerial   = _filterHasSerial == null || (_filterHasSerial == true ? r.serialNumber != null : r.serialNumber == null);

      return matchSearch && matchStatus && matchCategory && matchImei && matchSerial;
    }).toList();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _filterStatus != 'All' || _filterCategory != 'All' ||
          _filterHasImei != null || _filterHasSerial != null;

  Color _statusColor(String status) {
    switch (status) {
      case 'investigating': return Colors.orange;
      case 'resolved':      return Colors.green;
      default:              return _kPrimary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'investigating': return Icons.manage_search;
      case 'resolved':      return Icons.check_circle_outline;
      default:              return Icons.hourglass_empty;
    }
  }

  void _showFilterSheet() {
    String tempStatus   = _filterStatus;
    String tempCategory = _filterCategory;
    bool?  tempHasImei  = _filterHasImei;
    bool?  tempHasSerial = _filterHasSerial;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.5,
          builder: (_, ctrl) => Container(
            decoration: const BoxDecoration(
              color        : Colors.white,
              borderRadius : BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),

                // Title row
                Row(
                  children: [
                    const Icon(Icons.tune, color: _kPrimary, size: 22),
                    const SizedBox(width: 8),
                    Text('Filter Reports',
                        style: AppTheme.heading(18, color: _kPrimaryDark)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setSheetState(() {
                        tempStatus    = 'All';
                        tempCategory  = 'All';
                        tempHasImei   = null;
                        tempHasSerial = null;
                      }),
                      child: const Text('Reset', style: TextStyle(color: _kPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Divider(),
                const SizedBox(height: 16),

                // ── Device Category ────────────────────────────
                const _FilterSectionHeader(
                    icon: Icons.devices_outlined, label: 'Device Category'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _FilterChipOption(
                      label: 'All', icon: Icons.apps,
                      selected: tempCategory == 'All',
                      onTap: () => setSheetState(() => tempCategory = 'All'),
                    ),
                    _FilterChipOption(
                      label: 'Smartphone', icon: Icons.smartphone_outlined,
                      selected: tempCategory == 'phone',
                      onTap: () => setSheetState(() => tempCategory = 'phone'),
                    ),
                    _FilterChipOption(
                      label: 'Laptop', icon: Icons.laptop_outlined,
                      selected: tempCategory == 'laptop',
                      onTap: () => setSheetState(() => tempCategory = 'laptop'),
                    ),
                    _FilterChipOption(
                      label: 'Tablet', icon: Icons.tablet_outlined,
                      selected: tempCategory == 'tablet',
                      onTap: () => setSheetState(() => tempCategory = 'tablet'),
                    ),
                    _FilterChipOption(
                      label: 'Smartwatch', icon: Icons.watch_outlined,
                      selected: tempCategory == 'watch',
                      onTap: () => setSheetState(() => tempCategory = 'watch'),
                    ),
                    _FilterChipOption(
                      label: 'Other', icon: Icons.electrical_services_outlined,
                      selected: tempCategory == 'other',
                      onTap: () => setSheetState(() => tempCategory = 'other'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Status ─────────────────────────────────────
                const _FilterSectionHeader(
                    icon: Icons.info_outline, label: 'Status'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ['All', 'pending', 'investigating', 'resolved'].map((s) {
                    final col = s == 'pending'       ? _kPrimary
                        : s == 'investigating' ? Colors.orange
                        : s == 'resolved'      ? Colors.green
                        : Colors.grey[700]!;
                    return _FilterChipOption(
                      label: s == 'All' ? 'All' : s[0].toUpperCase() + s.substring(1),
                      selected: tempStatus == s,
                      onTap: () => setSheetState(() => tempStatus = s),
                      selectedColor: col,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // ── IMEI Verification ──────────────────────────
                const _FilterSectionHeader(
                    icon: Icons.verified_user_outlined,
                    label: 'IMEI Verification'),
                const SizedBox(height: 6),
                Text('Filter reports that have IMEI number on file',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _FilterChipOption(
                      label: 'All', selected: tempHasImei == null,
                      onTap: () => setSheetState(() => tempHasImei = null),
                    ),
                    _FilterChipOption(
                      label: '✓ IMEI Provided',
                      icon: Icons.verified_user_outlined,
                      selected: tempHasImei == true,
                      onTap: () => setSheetState(() => tempHasImei = true),
                      selectedColor: Colors.teal,
                    ),
                    _FilterChipOption(
                      label: '✗ No IMEI',
                      selected: tempHasImei == false,
                      onTap: () => setSheetState(() => tempHasImei = false),
                      selectedColor: Colors.grey[600]!,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Serial Number Verification ─────────────────
                const _FilterSectionHeader(
                    icon: Icons.qr_code_scanner,
                    label: 'Serial No. Verification'),
                const SizedBox(height: 6),
                Text('Filter reports that have a serial number on file',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _FilterChipOption(
                      label: 'All', selected: tempHasSerial == null,
                      onTap: () => setSheetState(() => tempHasSerial = null),
                    ),
                    _FilterChipOption(
                      label: '✓ S/N Provided',
                      icon: Icons.qr_code_scanner,
                      selected: tempHasSerial == true,
                      onTap: () => setSheetState(() => tempHasSerial = true),
                      selectedColor: Colors.teal,
                    ),
                    _FilterChipOption(
                      label: '✗ No S/N',
                      selected: tempHasSerial == false,
                      onTap: () => setSheetState(() => tempHasSerial = false),
                      selectedColor: Colors.grey[600]!,
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Buttons ────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: _kPrimary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: _kPrimary)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _filterStatus   = tempStatus;
                            _filterCategory = tempCategory;
                            _filterHasImei  = tempHasImei;
                            _filterHasSerial = tempHasSerial;
                            _applyFilters();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Apply Filters', style: AppTheme.heading(14, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        // ── Search bar + filter ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText  : 'Search by name, IMEI, serial no...',
                    hintStyle : TextStyle(color: Colors.grey[400], fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: _kPrimary, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() { _searchQuery = ''; _applyFilters(); });
                      },
                    ) : null,
                    filled    : true,
                    fillColor : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey[200]!)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.primaryStart, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Filter button
              Stack(
                children: [
                  Material(
                    color        : _kPrimary,
                    borderRadius : BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _showFilterSheet,
                      child: const Padding(
                        padding: EdgeInsets.all(13),
                        child: Icon(Icons.tune, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                  if (_hasActiveFilters)
                    Positioned(
                      right: 6, top: 6,
                      child: Container(
                        width: 9, height: 9,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ── Active filter chips ──────────────────────────────
        if (_hasActiveFilters)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Filters: ',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                  if (_filterCategory != 'All')
                    _ActiveChip(
                      label: _filterCategory[0].toUpperCase() + _filterCategory.substring(1),
                      onRemove: () => setState(() { _filterCategory = 'All'; _applyFilters(); }),
                    ),
                  if (_filterStatus != 'All') ...[
                    const SizedBox(width: 6),
                    _ActiveChip(
                      label: _filterStatus[0].toUpperCase() + _filterStatus.substring(1),
                      onRemove: () => setState(() { _filterStatus = 'All'; _applyFilters(); }),
                    ),
                  ],
                  if (_filterHasImei != null) ...[
                    const SizedBox(width: 6),
                    _ActiveChip(
                      label: _filterHasImei! ? 'IMEI ✓' : 'No IMEI',
                      onRemove: () => setState(() { _filterHasImei = null; _applyFilters(); }),
                    ),
                  ],
                  if (_filterHasSerial != null) ...[
                    const SizedBox(width: 6),
                    _ActiveChip(
                      label: _filterHasSerial! ? 'S/N ✓' : 'No S/N',
                      onRemove: () => setState(() { _filterHasSerial = null; _applyFilters(); }),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // ── Result count ─────────────────────────────────────
        if (!_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_filtered.length} report${_filtered.length == 1 ? '' : 's'} found',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
              ),
            ),
          ),

        // ── List ─────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : _filtered.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 14),
                Text(
                  _all.isEmpty
                      ? 'No stolen reports submitted yet.'
                      : 'No reports match your search.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 15),
                ),
                if (_all.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _searchQuery     = '';
                        _filterStatus    = 'All';
                        _filterCategory  = 'All';
                        _filterHasImei   = null;
                        _filterHasSerial = null;
                        _applyFilters();
                      });
                    },
                    child: const Text('Clear all filters',
                        style: TextStyle(color: _kPrimary)),
                  ),
                ],
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: _filtered.length,
            itemBuilder: (ctx, i) {
              final r     = _filtered[i];
              final isOwn = r.userId == FirebaseAuth.instance.currentUser?.uid;
              return _ElectronicsReportCard(
                report      : r,
                statusColor : _statusColor(r.status),
                statusIcon  : _statusIcon(r.status),
                isOwn       : isOwn,
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _ReportDetailSheet(report: r),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  FILTER SECTION HEADER
// ─────────────────────────────────────────────────────────────
class _FilterSectionHeader extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _FilterSectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: _kPrimary),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13.5, color: _kPrimaryDark)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  FILTER CHIP OPTION
// ─────────────────────────────────────────────────────────────
class _FilterChipOption extends StatelessWidget {
  final String   label;
  final IconData? icon;
  final bool     selected;
  final VoidCallback onTap;
  final Color    selectedColor;

  const _FilterChipOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.selectedColor = _kPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? selectedColor : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? Colors.white : Colors.grey[600]),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : Colors.grey[700],
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ACTIVE FILTER CHIP
// ─────────────────────────────────────────────────────────────
class _ActiveChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _ActiveChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color        : _kPrimary.withOpacity(0.1),
        borderRadius : BorderRadius.circular(20),
        border       : Border.all(color: _kPrimary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: _kPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 13, color: _kPrimary),
          ),
        ],
      ),
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
      initialChildSize: 0.70,
      maxChildSize    : 0.95,
      minChildSize    : 0.45,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color        : Colors.white,
          borderRadius : BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color        : _kPrimary.withOpacity(0.1),
                    borderRadius : BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.smartphone_outlined, color: _kPrimary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Report Details',
                          style: AppTheme.heading(20, color: _kPrimaryDark)),
                      Text('Filed on ${DateFormat('MMM dd, yyyy').format(report.createdAt)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Detail rows
            _detailRow(Icons.inventory_2_outlined,          'Asset',   report.assetName),
            _detailRow(Icons.devices_outlined,               'Category',
                _categoryLabel(report.deviceCategory)),
            _detailRow(Icons.tag,                            'Asset ID', report.assetId),
            _detailRow(Icons.account_balance_wallet_outlined,'Wallet',
                '${report.walletAddress.substring(0, 8)}...${report.walletAddress.substring(report.walletAddress.length - 6)}'),
            _detailRow(Icons.info_outline, 'Status',
                report.status[0].toUpperCase() + report.status.substring(1)),

            // IMEI & Serial
            if (report.imei != null) ...[
              const Divider(height: 24),
              const _FilterSectionHeader(icon: Icons.verified_user_outlined, label: 'Device Identifiers'),
              const SizedBox(height: 10),
              if (report.imei != null)
                _detailRow(Icons.verified_user_outlined, 'IMEI', report.imei!),
              if (report.serialNumber != null)
                _detailRow(Icons.qr_code_scanner, 'Serial No.', report.serialNumber!),
            ],

            const Divider(height: 28),
            Text('Description',
                style: AppTheme.heading(14, color: _kPrimaryDark)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color        : AppTheme.background,
                borderRadius : BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryStart.withOpacity(0.15)),
              ),
              child: Text(report.description,
                  style: const TextStyle(fontSize: 14, fontFamily: 'Poppins', height: 1.55)),
            ),

            if (report.docIpfsHash != null) ...[
              const SizedBox(height: 20),
              Text('Attached Document',
                  style: AppTheme.heading(14, color: _kPrimaryDark)),
              const SizedBox(height: 8),
              _ViewableDocTile(
                  fileName: report.docFileName ?? 'Document',
                  ipfsHash: report.docIpfsHash!),
            ],
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String? cat) {
    switch (cat) {
      case 'phone':  return 'Smartphone';
      case 'laptop': return 'Laptop';
      case 'tablet': return 'Tablet';
      case 'watch':  return 'Smartwatch';
      case 'other':  return 'Other Electronics';
      default:       return 'Electronics';
    }
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _kPrimary),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TAB 3 – SUBMIT NEW REPORT  (electronics only + IMEI/Serial)
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

  final _formKey         = GlobalKey<FormState>();
  final _descController  = TextEditingController();
  final _imeiController  = TextEditingController();
  final _serialController = TextEditingController();

  List<Map<String, dynamic>> _userAssets   = [];
  Map<String, dynamic>?      _selectedAsset;
  bool   _loadingAssets = true;
  String _deviceCategory = 'phone';

  PlatformFile? _pickedFile;
  bool _uploadingDoc = false;
  bool _submitting   = false;

  @override
  void initState() {
    super.initState();
    _loadUserAssets();
  }

  @override
  void dispose() {
    _descController.dispose();
    _imeiController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAssets() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('assets').where('ownerId',  isEqualTo: uid).get(),
        FirebaseFirestore.instance.collection('assets').where('ownerUid', isEqualTo: uid).get(),
      ]);
      final seen   = <String>{};
      final assets = <Map<String, dynamic>>[];
      for (final snap in results) {
        for (final doc in snap.docs) {
          if (!seen.add(doc.id)) continue;
          final data = doc.data();
          final cat  = (data['category'] as String?) ?? 'electronics';
          // Only electronics assets
          if (cat == 'land') continue;
          assets.add({
            'id'             : doc.id,
            'name'           : (data['title'] as String?) ?? 'Asset #${doc.id.substring(0, 6)}',
            'type'           : cat,
            'tokenId'        : data['blockchainTokenId']?.toString() ?? '',
            'deviceCategory' : data['deviceCategory'] ?? 'phone',
            'imageUrl'       : data['imageUrl'] ?? data['assetImageUrl'],
          });
        }
      }
      if (mounted) setState(() { _userAssets = assets; _loadingAssets = false; });
    } catch (e) {
      debugPrint('Error loading assets: $e');
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

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

  // ── Validate IMEI (15-digit Luhn) ───────────────────────────
  bool _validateImei(String imei) {
    if (imei.length != 15 || !RegExp(r'^\d{15}$').hasMatch(imei)) return false;
    int total = 0;
    for (int i = 0; i < 15; i++) {
      int d = int.parse(imei[i]);
      if (i.isOdd) { d *= 2; if (d > 9) d -= 9; }
      total += d;
    }
    return total % 10 == 0;
  }

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
      String? docHash, docName;

      if (_pickedFile != null && _pickedFile!.bytes != null) {
        if (mounted) setState(() => _uploadingDoc = true);
        try {
          final result = await IPFSService().uploadFile(
            fileBytes: _pickedFile!.bytes!,
            fileName : _pickedFile!.name,
            metadata : {'type': 'stolen_report_document'},
          );
          if (!result.success || result.ipfsHash == null) {
            throw Exception(result.error ?? 'Unknown upload error');
          }
          docHash = result.ipfsHash;
          docName = _pickedFile!.name;
        } catch (e) {
          _showSnack('Document upload failed: $e', isError: true);
          setState(() { _submitting = false; _uploadingDoc = false; });
          return;
        }
        if (mounted) setState(() => _uploadingDoc = false);
      }

      String walletAddress = '';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users').doc(user.uid).get();
        walletAddress = userDoc.data()?['walletAddress'] ?? '';
      } catch (_) {}

      await FirebaseFirestore.instance.collection('stolen_reports').add({
        'userId'        : user.uid,
        'assetId'       : _selectedAsset!['id'],
        'assetType'     : 'electronics',
        'assetName'     : _selectedAsset!['name'],
        'tokenId'       : _selectedAsset!['tokenId'],
        'deviceCategory': _deviceCategory,
        'assetImageUrl' : _selectedAsset!['imageUrl'],
        'description'   : _descController.text.trim(),
        'imei'          : _imeiController.text.trim().isEmpty ? null : _imeiController.text.trim(),
        'serialNumber'  : _serialController.text.trim().isEmpty ? null : _serialController.text.trim(),
        'docIpfsHash'   : docHash,
        'docFileName'   : docName,
        'status'        : 'pending',
        'createdAt'     : FieldValue.serverTimestamp(),
        'walletAddress' : walletAddress,
      });

      await FirebaseFirestore.instance.collection('assets').doc(_selectedAsset!['id']).update({
        'isStolenReported' : true,
        'stolenReportedAt' : FieldValue.serverTimestamp(),
        'stolenReportedBy' : user.uid,
      });

      if (mounted) {
        _showSnack('Stolen report submitted successfully!');
        setState(() { _selectedAsset = null; _pickedFile = null; _deviceCategory = 'phone'; });
        _descController.clear();
        _imeiController.clear();
        _serialController.clear();
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
        content    : Text(msg),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior   : SnackBarBehavior.floating,
        shape      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {Widget? prefix}) {
    return InputDecoration(
      hintText  : hint,
      hintStyle : TextStyle(color: Colors.grey[400], fontSize: 13),
      prefixIcon: prefix,
      filled    : true,
      fillColor : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryStart, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Info banner ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color        : const Color(0xFFFFF3E0),
                borderRadius : BorderRadius.circular(14),
                border       : Border.all(color: Colors.orange[300]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You can only report electronics assets you currently own. '
                          'Providing IMEI or serial number greatly speeds up investigation. '
                          'Attach your police complaint document for faster processing.',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.orange[800], height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Device Category ──────────────────────────────
            const _SectionLabel(icon: Icons.devices_outlined, text: 'Device Category'),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CategoryButton(
                    icon: Icons.smartphone_outlined, label: 'Smartphone',
                    selected: _deviceCategory == 'phone',
                    onTap: () => setState(() => _deviceCategory = 'phone'),
                  ),
                  const SizedBox(width: 8),
                  _CategoryButton(
                    icon: Icons.laptop_outlined, label: 'Laptop',
                    selected: _deviceCategory == 'laptop',
                    onTap: () => setState(() => _deviceCategory = 'laptop'),
                  ),
                  const SizedBox(width: 8),
                  _CategoryButton(
                    icon: Icons.tablet_outlined, label: 'Tablet',
                    selected: _deviceCategory == 'tablet',
                    onTap: () => setState(() => _deviceCategory = 'tablet'),
                  ),
                  const SizedBox(width: 8),
                  _CategoryButton(
                    icon: Icons.watch_outlined, label: 'Watch',
                    selected: _deviceCategory == 'watch',
                    onTap: () => setState(() => _deviceCategory = 'watch'),
                  ),
                  const SizedBox(width: 8),
                  _CategoryButton(
                    icon: Icons.electrical_services_outlined, label: 'Other',
                    selected: _deviceCategory == 'other',
                    onTap: () => setState(() => _deviceCategory = 'other'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Select Asset ─────────────────────────────────
            const _SectionLabel(icon: Icons.inventory_2_outlined, text: 'Select Stolen Device'),
            const SizedBox(height: 10),
            _loadingAssets
                ? const Center(child: CircularProgressIndicator(color: _kPrimary))
                : _userAssets.isEmpty
                ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color        : Colors.grey[100],
                borderRadius : BorderRadius.circular(12),
                border       : Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.grey[400]),
                  const SizedBox(width: 10),
                  Text('You have no electronics assets to report.',
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            )
                : DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedAsset,
              isExpanded: true,
              decoration: _inputDecoration('Choose your device'),
              items: _userAssets.map((asset) {
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: asset,
                  child: Text('📱  ${asset['name']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedAsset = val),
              validator: (val) => val == null ? 'Please select an asset' : null,
            ),
            const SizedBox(height: 24),

            // ── IMEI ─────────────────────────────────────────
            const _SectionLabel(
                icon: Icons.verified_user_outlined, text: 'IMEI Number'),
            const SizedBox(height: 4),
            Text(
              'Recommended for smartphones & tablets (15-digit number)',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller  : _imeiController,
              keyboardType: TextInputType.number,
              maxLength   : 15,
              decoration  : _inputDecoration(
                'Enter 15-digit IMEI (dial *#06# to find it)',
                prefix: const Icon(Icons.verified_user_outlined,
                    color: _kPrimary, size: 20),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return null; // optional
                if (!_validateImei(val.trim())) {
                  return 'Invalid IMEI — must be 15 digits and pass Luhn check';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // ── Serial Number ────────────────────────────────
            const _SectionLabel(
                icon: Icons.qr_code_scanner, text: 'Serial Number'),
            const SizedBox(height: 4),
            Text(
              'Found on the device box, back panel, or Settings > About',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller  : _serialController,
              decoration  : _inputDecoration(
                'Enter device serial number (optional)',
                prefix: const Icon(Icons.qr_code_scanner,
                    color: _kPrimary, size: 20),
              ),
            ),
            const SizedBox(height: 24),

            // ── Description ──────────────────────────────────
            const _SectionLabel(
                icon: Icons.description_outlined, text: 'Incident Description'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descController,
              maxLines  : 5,
              decoration: _inputDecoration(
                  'Describe the theft incident (when, where, how...)'),
              validator: (val) {
                if (val == null || val.trim().isEmpty) return 'Description is required';
                if (val.trim().length < 20) return 'Provide at least 20 characters';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // ── Police Document ──────────────────────────────
            const _SectionLabel(
                icon: Icons.gavel_outlined, text: 'Police Complaint Document'),
            const SizedBox(height: 6),
            Text('Optional but recommended — PDF, image, or Word doc',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickDocument,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _pickedFile != null ? Colors.green[50] : _kBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _pickedFile != null
                        ? Colors.green[300]!
                        : _kPrimary.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _pickedFile != null ? Icons.check_circle : Icons.upload_file,
                      color: _pickedFile != null ? Colors.green[600] : _kPrimary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _pickedFile != null
                          ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_pickedFile!.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                          Text(
                            '${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB • Tap to change',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      )
                          : Text(
                        'Tap to attach police complaint document',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
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

            // ── Submit button ────────────────────────────────
            SizedBox(
              width : double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: (_submitting || _loadingAssets) ? null : _submitReport,
                icon: _submitting
                    ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined),
                label: Text(
                  _uploadingDoc
                      ? 'Uploading Document...'
                      : _submitting
                      ? 'Submitting...'
                      : 'Submit Stolen Report',
                  style: AppTheme.heading(16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 3,
                  shadowColor: _kPrimary.withOpacity(0.4),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  CATEGORY BUTTON
// ─────────────────────────────────────────────────────────────
class _CategoryButton extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     selected;
  final VoidCallback onTap;
  const _CategoryButton({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color        : selected ? _kPrimary : Colors.white,
          borderRadius : BorderRadius.circular(12),
          border       : Border.all(
              color: selected ? _kPrimary : Colors.grey[300]!),
          boxShadow: selected
              ? [BoxShadow(color: _kPrimary.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 3))]
              : [],
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: selected ? Colors.white : Colors.grey[600]),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : Colors.grey[700],
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  HELPER WIDGET – SECTION LABEL
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _kPrimary),
        const SizedBox(width: 7),
        Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: _kPrimaryDark)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  VIEWABLE DOCUMENT TILE
// ─────────────────────────────────────────────────────────────
class _ViewableDocTile extends StatelessWidget {
  final String fileName;
  final String ipfsHash;
  const _ViewableDocTile({required this.fileName, required this.ipfsHash});

  static const String _gateway = 'https://gateway.pinata.cloud/ipfs/';

  bool get _isImage {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }

  IconData get _icon {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':        return Icons.image_outlined;
      case 'doc':
      case 'docx':       return Icons.description_outlined;
      default:           return Icons.insert_drive_file_outlined;
    }
  }

  Color get _iconColor {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':        return Colors.red[600]!;
      case 'jpg':
      case 'jpeg':
      case 'png':        return Colors.blue[600]!;
      case 'doc':
      case 'docx':       return Colors.indigo[600]!;
      default:           return Colors.grey[600]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color        : Colors.green[50],
      borderRadius : BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _DocViewerScreen(
                fileName: fileName, ipfsUrl: '$_gateway$ipfsHash', isImage: _isImage),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border      : Border.all(color: Colors.green[300]!),
          ),
          child: Row(
            children: [
              Icon(_icon, color: _iconColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fileName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text('IPFS: ${ipfsHash.substring(0, 18)}...',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.visibility_outlined,
                            size: 11, color: Colors.green[700]),
                        const SizedBox(width: 3),
                        Text('Tap to view in app',
                            style: TextStyle(
                                fontSize: 11, color: Colors.green[700],
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, color: Colors.green[600], size: 16),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: Colors.green[600], size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  IN-APP DOCUMENT VIEWER SCREEN
// ─────────────────────────────────────────────────────────────
class _DocViewerScreen extends StatefulWidget {
  final String fileName;
  final String ipfsUrl;
  final bool   isImage;

  const _DocViewerScreen({
    required this.fileName,
    required this.ipfsUrl,
    required this.isImage,
  });

  @override
  State<_DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<_DocViewerScreen> {
  late final WebViewController _webCtrl;
  bool _webLoading = true;
  bool _webError   = false;

  String get _googleDocsUrl =>
      'https://docs.google.com/viewer?embedded=true&url=${Uri.encodeComponent(widget.ipfsUrl)}';

  @override
  void initState() {
    super.initState();
    if (!widget.isImage) _initWebView();
  }

  void _initWebView() {
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted : (_) => setState(() { _webLoading = true;  _webError = false; }),
        onPageFinished: (_) => setState(() => _webLoading = false),
        onWebResourceError: (err) {
          if (err.isForMainFrame ?? true) {
            setState(() { _webLoading = false; _webError = true; });
          }
        },
      ))
      ..loadRequest(Uri.parse(_googleDocsUrl));
  }

  void _reload() {
    setState(() { _webLoading = true; _webError = false; });
    _webCtrl.loadRequest(Uri.parse(_googleDocsUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation      : 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.fileName,
                style: AppTheme.heading(14, color: Colors.white),
                overflow: TextOverflow.ellipsis),
            Text('Police Complaint Document',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
          ],
        ),
        actions: [
          if (!widget.isImage)
            IconButton(
              icon   : const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: _reload,
            ),
        ],
      ),
      body: widget.isImage ? _buildImageViewer() : _buildWebViewer(),
    );
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.network(
          widget.ipfsUrl,
          fit: BoxFit.contain,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                        : null,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  const Text('Loading image...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            );
          },
          errorBuilder: (_, __, ___) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 64),
                const SizedBox(height: 12),
                const Text('Could not load image',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    final fallback = widget.ipfsUrl.replaceFirst(
                      'https://gateway.pinata.cloud/ipfs/',
                      'https://ipfs.io/ipfs/',
                    );
                    Navigator.pushReplacement(context,
                      MaterialPageRoute(
                        builder: (_) => _DocViewerScreen(
                          fileName: widget.fileName,
                          ipfsUrl : fallback,
                          isImage : true,
                        ),
                      ),
                    );
                  },
                  child: const Text('Try alternate gateway',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebViewer() {
    return Stack(
      children: [
        WebViewWidget(controller: _webCtrl),
        if (_webLoading)
          Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _kPrimary),
                  SizedBox(height: 16),
                  Text('Loading document...',
                      style: TextStyle(color: _kPrimary, fontWeight: FontWeight.w500)),
                  SizedBox(height: 8),
                  Text('Using Google Docs viewer',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ),
        if (_webError && !_webLoading)
          Container(
            color: Colors.white,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('Could not load document',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Google Docs viewer may need a moment. Tap retry.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _reload,
                      icon : const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}