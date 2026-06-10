// lib/screens/land_fractions_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../blockchain/blockchain_service.dart';
import '../services/push_notification_service.dart';
import '../theme.dart';

class LandFractionsScreen extends StatefulWidget {
  final String assetId;
  final int    blockchainPropertyId;

  const LandFractionsScreen({
    super.key,
    required this.assetId,
    required this.blockchainPropertyId,
  });

  @override
  State<LandFractionsScreen> createState() => _LandFractionsScreenState();
}

class _LandFractionsScreenState extends State<LandFractionsScreen>
    with SingleTickerProviderStateMixin {
  final _blockchainService = BlockchainServiceEnhanced();
  final _notif = PushNotificationService();
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _propertyData;
  int  _selectedFractions  = 1;
  bool _loading            = true;
  int  _userFractions      = 0;
  bool _hasExistingRequest = false;
  bool _checkingRequest    = false;

  // Page entrance animation
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550))
      ..forward();
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
        begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _loadPropertyData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadPropertyData() async {
    try {
      await _blockchainService.init();
      final property = await _blockchainService
          .getLandProperty(widget.blockchainPropertyId);

      if (_blockchainService.isConnected) {
        _userFractions = await _blockchainService.getUserFractions(
          _blockchainService.connectedAddress!,
          widget.blockchainPropertyId,
        );
      }
      await _checkExistingRequest();
      
      // --- SECURITY & SELF-HEALING ---
      bool isHealthy = await _blockchainService.verifyAndHealAsset(
        type: 'land',
        blockchainId: widget.blockchainPropertyId,
        firestoreDocId: widget.assetId,
        firestore: _db,
      );
      if (!isHealthy && mounted) {
        _showSnack('Security Update: Asset data synchronized with Blockchain', color: Colors.blueAccent);
      }
      // -------------------------------

      setState(() {
        _propertyData = property;
        _loading      = false;
      });
    } catch (e) {
      debugPrint('Error loading property: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _checkExistingRequest() async {
    final user = _auth.currentUser;
    if (user == null) return;
    setState(() => _checkingRequest = true);
    try {
      final existing = await _db
          .collection('fraction_requests')
          .where('assetId',   isEqualTo: widget.assetId)
          .where('buyerUid',  isEqualTo: user.uid)
          .where('status',    whereIn: ['pending', 'approved'])
          .limit(1)
          .get();
      setState(() {
        _hasExistingRequest = existing.docs.isNotEmpty;
        _checkingRequest    = false;
      });
    } catch (_) {
      setState(() => _checkingRequest = false);
    }
  }

  // ── Purchase request ──────────────────────────────────────────────────────
  Future<void> _sendPurchaseRequest() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showSnack('Please login to continue');
      return;
    }
    if (_propertyData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text('Confirm Request',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize     : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogRow(
              label: 'Fractions requested',
              value: '$_selectedFractions',
            ),
            const SizedBox(height: 8),
            _DialogRow(
              label: 'Price per fraction',
              value:
              '${_formatPrice(_propertyData!['pricePerFraction'])} MATIC',
            ),
            const SizedBox(height: 8),
            Container(
              padding   : const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color       : AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Estimated Total',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          color     : AppTheme.textPrimary)),
                  Text(
                    '${_formatPrice(_calculateTotal())} MATIC',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize  : 16,
                      color     : AppTheme.primaryStart,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A purchase request will be sent to the supplier. '
                  'The blockchain transaction will only proceed once approved.',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppTheme.textMid, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child    : Text('Cancel',
                style: GoogleFonts.poppins(color: AppTheme.textMid)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient    : const LinearGradient(
                  colors: [AppTheme.primaryStartDark, AppTheme.primaryEnd]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              color       : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child       : InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap       : () => Navigator.pop(ctx, true),
                child       : Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  child: Text('Send Request',
                      style: GoogleFonts.poppins(
                          color     : Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _loading = true);

    try {
      final assetDoc  = await _db.collection('assets').doc(widget.assetId).get();
      final sellerUid = assetDoc.data()?['ownerId'] ??
          assetDoc.data()?['ownerUid'];
      if (sellerUid == null) throw Exception('Could not find the asset owner.');
      final propertyLabel =
          assetDoc.data()?['title']?.toString() ??
          _propertyData?['location']?.toString() ??
          'property';
      final buyerName =
          user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : (user.email?.trim().isNotEmpty == true
                  ? user.email!.trim()
                  : 'A buyer');

      final sharedId = _db.collection('fraction_requests').doc().id;
      final batch    = _db.batch();

      batch.set(_db.collection('fraction_requests').doc(sharedId), {
        'assetId'             : widget.assetId,
        'blockchainPropertyId': widget.blockchainPropertyId,
        'buyerUid'            : user.uid,
        'sellerUid'           : sellerUid,
        'fractionsRequested'  : _selectedFractions,
        'pricePerFraction'    : _propertyData!['pricePerFraction'].toString(),
        'totalCost'           : _calculateTotal().toString(),
        'status'              : 'pending',
        'transactionId'       : sharedId,
        'createdAt'           : FieldValue.serverTimestamp(),
      });

      batch.set(_db.collection('transactions').doc(sharedId), {
        'transactionId'       : sharedId,
        'assetId'             : widget.assetId,
        'buyerUid'            : user.uid,
        'sellerUid'           : sellerUid,
        'status'              : 'pending',
        'category'            : 'land',
        'requestType'         : 'fraction_purchase',
        'fractionsRequested'  : _selectedFractions,
        'blockchainTokenId'   : widget.blockchainPropertyId,
        'blockchainPropertyId': widget.blockchainPropertyId,
        'createdAt'           : FieldValue.serverTimestamp(),
      });

      await batch.commit();
      await Future.wait([
        _notif.notify(
          receiverUid: user.uid,
          title: '✅ Fraction Request Sent',
          body:
              'Your request for $_selectedFractions fraction(s) of "$propertyLabel" has been sent.',
          type: NotificationType.transactionPending,
          relatedId: sharedId,
          payload: {
            'assetId': widget.assetId,
            'requestType': 'fraction_purchase',
          },
        ),
        _notif.notify(
          receiverUid: sellerUid.toString(),
          title: '📩 New Fraction Request',
          body:
              '$buyerName requested $_selectedFractions fraction(s) of "$propertyLabel".',
          type: NotificationType.transactionPending,
          relatedId: sharedId,
          payload: {
            'assetId': widget.assetId,
            'requestType': 'fraction_purchase',
            'buyerUid': user.uid,
          },
        ),
      ]);
      setState(() {
        _hasExistingRequest = true;
        _loading            = false;
      });
      if (mounted) {
        _showSnack(
          '✅ Request sent! You will be notified once the supplier responds.',
        color: Colors.green,
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _showSnack('Error: $e', color: Colors.red);
    }
  }

  BigInt _calculateTotal() {
    final ppf = _propertyData!['pricePerFraction'] as BigInt;
    return ppf * BigInt.from(_selectedFractions);
  }

  String _formatPrice(BigInt wei) =>
      _blockchainService.weiToEther(wei);

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content        : Text(msg, style: GoogleFonts.poppins()),
        backgroundColor: color ?? AppTheme.primaryStart,
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [AppTheme.primaryStartDark, AppTheme.primaryStart],
                begin : Alignment.topLeft,
                end   : Alignment.bottomRight),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
    }

    if (_propertyData == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar          : _buildAppBar(),
        body            : Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppTheme.textMid),
              const SizedBox(height: 12),
              Text('Failed to load property data',
                  style: GoogleFonts.poppins(
                      color: AppTheme.textMid, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    final totalFractions     = _propertyData!['totalFractions'] as int;
    final availableFractions = totalFractions - _userFractions;
    final canRequest         = availableFractions > 0 && !_hasExistingRequest;
    final ownershipPct       = totalFractions > 0
        ? (_userFractions / totalFractions * 100)
        : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildAppBarWidget(totalFractions, ownershipPct),
          Expanded(
            child: FadeTransition(
              opacity : _fadeAnim,
              child   : SlideTransition(
                position: _slideAnim,
                child   : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child  : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Property info
                      _buildPropertyCard(totalFractions),
                      const SizedBox(height: 16),

                      // Pending request banner
                      if (_hasExistingRequest) ...[
                        _buildStatusBanner(
                          icon : Icons.hourglass_top_rounded,
                          color: Colors.orange,
                          title: 'Request Pending',
                          body : 'You already have a pending request. '
                              'Please wait for the supplier to respond.',
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Fraction selector
                      if (availableFractions > 0 && canRequest) ...[
                        _buildSectionLabel('Select Fractions'),
                        const SizedBox(height: 12),
                        _buildFractionSelector(availableFractions),
                        const SizedBox(height: 16),
                      ],

                      // Price summary
                      _buildSectionLabel('Price Summary'),
                      const SizedBox(height: 10),
                      _buildPriceCard(),
                      const SizedBox(height: 16),

                      // After-approval preview
                      if (canRequest) ...[
                        _buildSectionLabel('If Approved'),
                        const SizedBox(height: 10),
                        _buildApprovalPreview(totalFractions),
                        const SizedBox(height: 28),
                        _buildCTAButton(),
                        const SizedBox(height: 14),
                        _buildInfoNote(),
                      ] else if (availableFractions > 0 &&
                          _hasExistingRequest) ...[
                        _buildStatusBanner(
                          icon : Icons.access_time_rounded,
                          color: Colors.orange,
                          title: 'Awaiting Approval',
                          body : 'Your request is pending supplier approval.',
                        ),
                      ] else ...[
                        _buildStatusBanner(
                          icon : Icons.check_circle_rounded,
                          color: Colors.green,
                          title: 'Full Ownership',
                          body : 'You own 100% of this property!',
                        ),
                      ],
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

  // ── App bar (plain, used for error/loading states) ────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.primaryStart,
      flexibleSpace  : Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [AppTheme.primaryStartDark, AppTheme.primaryStart],
              begin : Alignment.topLeft,
              end   : Alignment.bottomRight),
        ),
      ),
      leading: IconButton(
        icon     : const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Request Fractions',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  // ── Gradient header with stats ────────────────────────────────────────────
  Widget _buildAppBarWidget(int totalFractions, double ownershipPct) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [AppTheme.primaryStartDark, AppTheme.primaryStart],
            begin : Alignment.topLeft,
            end   : Alignment.bottomRight),
        borderRadius: BorderRadius.only(
          bottomLeft : Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child : Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child  : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding   : const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color       : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('Request Fractions',
                      style: GoogleFonts.poppins(
                        fontSize  : 18,
                        fontWeight: FontWeight.w700,
                        color     : Colors.white,
                      )),
                ],
              ),
              const SizedBox(height: 20),

              // Ownership stats row
              Row(
                children: [
                  _HeaderStat(
                    label: 'Total Fractions',
                    value: '$totalFractions',
                    icon : Icons.grid_view_rounded,
                  ),
                  const SizedBox(width: 12),
                  _HeaderStat(
                    label: 'You Own',
                    value: '$_userFractions',
                    icon : Icons.account_balance_wallet_rounded,
                  ),
                  const SizedBox(width: 12),
                  _HeaderStat(
                    label: 'Ownership',
                    value: '${ownershipPct.toStringAsFixed(1)}%',
                    icon : Icons.pie_chart_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Property info card ────────────────────────────────────────────────────
  Widget _buildPropertyCard(int totalFractions) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding   : const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color       : AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: AppTheme.primaryStart, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _propertyData!['location'] ?? '—',
                      style: GoogleFonts.poppins(
                          fontSize  : 16,
                          fontWeight: FontWeight.w700,
                          color     : AppTheme.textPrimary),
                    ),
                    Text(
                      _propertyData!['city'] ?? '',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: AppTheme.textMid),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppTheme.primaryStart.withOpacity(0.1)),
          const SizedBox(height: 10),
          Row(
            children: [
              _InfoChip(
                icon : Icons.straighten_rounded,
                label:
                '${_propertyData!['totalArea']} ${_propertyData!['areaUnit']}',
              ),
              const SizedBox(width: 10),
              _InfoChip(
                icon : Icons.token_rounded,
                label: 'Token #${widget.blockchainPropertyId}',
              ),
            ],
          ),

          // Ownership progress bar
          const SizedBox(height: 16),
          Text('Your ownership',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppTheme.textMid)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child       : LinearProgressIndicator(
              value          : totalFractions > 0
                  ? _userFractions / totalFractions
                  : 0,
              minHeight      : 8,
              backgroundColor: AppTheme.primaryLight,
              valueColor     : const AlwaysStoppedAnimation<Color>(AppTheme.primaryStart),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_userFractions owned',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppTheme.textMid)),
              Text('$totalFractions total',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppTheme.textMid)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Fraction slider ───────────────────────────────────────────────────────
  Widget _buildFractionSelector(int availableFractions) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fractions to request',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppTheme.textMid)),
              Container(
                padding   : const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color       : AppTheme.primaryStart,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_selectedFractions',
                  style: GoogleFonts.poppins(
                    color     : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize  : 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor  : AppTheme.primaryStart,
              inactiveTrackColor: AppTheme.primaryLight,
              thumbColor        : AppTheme.primaryStartDark,
              overlayColor      : AppTheme.primaryStart.withOpacity(0.15),
              trackHeight       : 6,
            ),
            child: Slider(
              value    : _selectedFractions.toDouble(),
              min      : 1,
              max      : availableFractions.toDouble(),
              divisions: availableFractions > 1
                  ? availableFractions - 1
                  : null,
              label    : _selectedFractions.toString(),
              onChanged: (v) =>
                  setState(() => _selectedFractions = v.toInt()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppTheme.textMid)),
              Text('$availableFractions available',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppTheme.textMid)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Price card ────────────────────────────────────────────────────────────
  Widget _buildPriceCard() {
    return _Card(
      child: Column(
        children: [
          _PriceRow(
            icon      : Icons.sell_rounded,
            label     : 'Price per fraction',
            value     :
            '${_formatPrice(_propertyData!['pricePerFraction'])} MATIC',
            iconColor : AppTheme.primaryStart,
          ),
          Divider(height: 18, color: AppTheme.primaryStart.withOpacity(0.1)),
          _PriceRow(
            icon     : Icons.layers_rounded,
            label    : 'Fractions selected',
            value    : '$_selectedFractions',
            iconColor: AppTheme.primaryEnd,
          ),
          Divider(height: 18, color: AppTheme.primaryStart.withOpacity(0.1)),
          Container(
            padding   : const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color       : AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded,
                        color: AppTheme.primaryStart, size: 18),
                    const SizedBox(width: 8),
                    Text('Estimated Total',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize  : 14,
                          color     : AppTheme.textPrimary,
                        )),
                  ],
                ),
                Text(
                  '${_formatPrice(_calculateTotal())} MATIC',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize  : 15,
                    color     : AppTheme.primaryStart,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Approval preview ──────────────────────────────────────────────────────
  Widget _buildApprovalPreview(int totalFractions) {
    final newTotal = _userFractions + _selectedFractions;
    final newPct   = totalFractions > 0
        ? (newTotal / totalFractions * 100)
        : 0.0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding   : const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color       : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.trending_up_rounded,
                    color: Colors.green, size: 20),
              ),
              const SizedBox(width: 10),
              Text('After Approval',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize  : 14,
                    color     : AppTheme.textPrimary,
                  )),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _PreviewStat(
                  label: 'Your Fractions',
                  value: '$newTotal',
                  color: AppTheme.primaryStart,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PreviewStat(
                  label: 'Ownership %',
                  value: '${newPct.toStringAsFixed(2)}%',
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child       : LinearProgressIndicator(
              value          : totalFractions > 0 ? newTotal / totalFractions : 0,
              minHeight      : 8,
              backgroundColor: AppTheme.primaryLight,
              valueColor     : const AlwaysStoppedAnimation<Color>(AppTheme.primaryStart),
            ),
          ),
        ],
      ),
    );
  }

  // ── CTA button ────────────────────────────────────────────────────────────
  Widget _buildCTAButton() {
    return AnimatedContainer(
      duration   : const Duration(milliseconds: 200),
      height     : 54,
      decoration : BoxDecoration(
        gradient    : _checkingRequest
            ? null
            : const LinearGradient(
            colors: [AppTheme.primaryStartDark, AppTheme.primaryEnd],
            begin : Alignment.topLeft,
            end   : Alignment.bottomRight),
        color       : _checkingRequest ? Colors.grey.shade300 : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow   : _checkingRequest
            ? []
            : [
          BoxShadow(
            color     : AppTheme.primaryStart.withOpacity(0.35),
            blurRadius: 14,
            offset    : const Offset(0, 5),
          )
        ],
      ),
      child: Material(
        color       : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child       : InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap       : _checkingRequest ? null : _sendPurchaseRequest,
          child       : Center(
            child: _checkingRequest
                ? const SizedBox(
              width : 22,
              height: 22,
              child : CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
                : Row(
              mainAxisSize: MainAxisSize.min,
              children    : [
                const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Request to Purchase Fractions',
                  style: GoogleFonts.poppins(
                    color     : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize  : 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Info note ─────────────────────────────────────────────────────────────
  Widget _buildInfoNote() {
    return Container(
      padding   : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: AppTheme.primaryStart.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding   : const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color       : AppTheme.primaryStart.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.info_outline_rounded,
                size: 18, color: AppTheme.primaryStart),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No payment or wallet transaction will occur now. '
                  'The blockchain transaction only happens after supplier approval.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color   : AppTheme.primaryStartDark,
                height  : 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status banner ─────────────────────────────────────────────────────────
  Widget _buildStatusBanner({
    required IconData icon,
    required Color    color,
    required String   title,
    required String   body,
  }) {
    return Container(
      padding   : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding   : const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color       : color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize  : 13,
                        color     : color)),
                const SizedBox(height: 2),
                Text(body,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color   : color.withOpacity(0.8),
                        height  : 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child  : Text(text,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          fontSize  : 14,
          color     : AppTheme.textPrimary,
        )),
  );
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color       : Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow   : [
        BoxShadow(
          color     : AppTheme.primaryStart.withOpacity(0.07),
          blurRadius: 14,
          offset    : const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _HeaderStat extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  const _HeaderStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding   : const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color       : Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.poppins(
                color     : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize  : 16,
              )),
          Text(label,
              style: GoogleFonts.poppins(
                color   : Colors.white70,
                fontSize: 10,
              ),
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color       : AppTheme.primaryLight,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children    : [
        Icon(icon, size: 14, color: AppTheme.primaryStart),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12,
                color   : AppTheme.primaryStart,
                fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _PriceRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    iconColor;
  const _PriceRow(
      {required this.icon,
        required this.label,
        required this.value,
        required this.iconColor});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: iconColor),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppTheme.textMid)),
      ),
      Text(value,
          style: GoogleFonts.poppins(
              fontSize  : 13,
              fontWeight: FontWeight.w600,
              color     : AppTheme.textPrimary)),
    ],
  );
}

class _PreviewStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _PreviewStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color       : color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      border      : Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(
      children: [
        Text(value,
            style: GoogleFonts.poppins(
              fontSize  : 20,
              fontWeight: FontWeight.w800,
              color     : color,
            )),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11, color: AppTheme.textMid),
            textAlign: TextAlign.center),
      ],
    ),
  );
}

class _DialogRow extends StatelessWidget {
  final String label;
  final String value;
  const _DialogRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label,
          style: GoogleFonts.poppins(
              fontSize: 13, color: AppTheme.textMid)),
      Text(value,
          style: GoogleFonts.poppins(
              fontSize  : 13,
              fontWeight: FontWeight.w600,
              color     : AppTheme.textPrimary)),
    ],
  );
}
