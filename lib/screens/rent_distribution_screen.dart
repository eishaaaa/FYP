// lib/screens/rent_distribution_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../blockchain/blockchain_service.dart';
import '../theme.dart';
import '../widgets/rent_actions.dart';

// Brand colors removed - using AppTheme

class RentDistributionScreen extends StatefulWidget {
  final String assetId;
  final int    propertyId;
  final bool   isOwner;

  const RentDistributionScreen({
    super.key,
    required this.assetId,
    required this.propertyId,
    this.isOwner = false,
  });

  @override
  State<RentDistributionScreen> createState() =>
      _RentDistributionScreenState();
}

class _RentDistributionScreenState extends State<RentDistributionScreen>
    with SingleTickerProviderStateMixin {
  final _blockchainService = BlockchainServiceEnhanced();
  final _amountCtrl        = TextEditingController();
  final _rentPriceCtrl     = TextEditingController();
  final _db                = FirebaseFirestore.instance;
  final _auth              = FirebaseAuth.instance;

  Map<String, dynamic>? _propertyData;
  BigInt _unclaimedRent = BigInt.zero;
  int    _userFractions = 0;
  bool   _loading       = true;

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
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _amountCtrl.dispose();
    _rentPriceCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      await _blockchainService.init();
      final property =
      await _blockchainService.getLandProperty(widget.propertyId);

      if (_blockchainService.isConnected) {
        _unclaimedRent = await _blockchainService.getUnclaimedRent(
          _blockchainService.connectedAddress!,
          widget.propertyId,
        );
        _userFractions = await _blockchainService.getUserFractions(
          _blockchainService.connectedAddress!,
          widget.propertyId,
        );
      }

      // Fetch owner info from Firestore
      final assetDoc = await _db.collection('assets').doc(widget.assetId).get();
      final ownerUid = assetDoc.data()?['ownerId'] ?? assetDoc.data()?['ownerUid'];
      
      setState(() {
        if (property != null) {
          _propertyData = Map<String, dynamic>.from(property);
          _propertyData!['originalOwnerUid'] = ownerUid;
        }
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // ── Distribute ────────────────────────────────────────────────────────────
  Future<void> _distributeRent() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _showSnack('Please enter a valid amount');
      return;
    }
    final weiAmount = _blockchainService.etherToWei(amount);
    _showProcessingDialog('Distributing rent…');
    try {
      if (!_blockchainService.isConnected) {
        await _blockchainService.connectWallet(context);
      }
      final txHash = await _blockchainService.distributeLandRent(
        propertyId: widget.propertyId,
        amount    : weiAmount,
      );
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (mounted) Navigator.pop(context);
        if (ok) {
          _showSnack('✅ Rent distributed successfully!',
              color: Colors.green);
          _amountCtrl.clear();
          _loadData();
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  // ── Rental Logic ──────────────────────────────────────────────────────────
  Future<void> _listForRent() async {
    final rentAmount = double.tryParse(_rentPriceCtrl.text);
    if (rentAmount == null || rentAmount <= 0) {
      _showSnack('Please enter a valid monthly rent');
      return;
    }
    final weiRent = _blockchainService.etherToWei(rentAmount);
    _showProcessingDialog('Listing for rent…');
    try {
      final txHash = await _blockchainService.listLandForRent(
        propertyId: widget.propertyId,
        rentAmount: weiRent,
      );
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (ok) {
          // Sync with Firestore
          await _db.collection('assets').doc(widget.assetId).update({
            'isForRent': true,
            'monthlyRent': rentAmount,
          });
          if (mounted) Navigator.pop(context);
          _showSnack('✅ Listed for rent successfully!', color: Colors.green);
          _loadData();
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  Future<void> _requestRent() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    _showProcessingDialog('Sending rent request…');
    try {
      final txHash = await _blockchainService.requestLandRent(widget.propertyId);
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (ok) {
          final requestId = _db.collection('rent_requests').doc().id;
          final batch = _db.batch();
          
          final rentAmount = _blockchainService.weiToEther(_propertyData!['monthlyRent']);

          batch.set(_db.collection('rent_requests').doc(requestId), {
            'assetId': widget.assetId,
            'propertyId': widget.propertyId,
            'tenantUid': user.uid,
            'ownerUid': _propertyData!['originalOwnerUid'] ?? '', // We'll need to ensure this is in _propertyData or fetched
            'rentAmount': rentAmount,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });

          batch.set(_db.collection('transactions').doc(requestId), {
            'transactionId': requestId,
            'assetId': widget.assetId,
            'buyerUid': user.uid, // tenant
            'sellerUid': _propertyData!['originalOwnerUid'] ?? '', // owner
            'status': 'pending',
            'category': 'land',
            'requestType': 'rent_request',
            'amount': rentAmount,
            'blockchainPropertyId': widget.propertyId,
            'createdAt': FieldValue.serverTimestamp(),
          });

          await batch.commit();
          if (mounted) Navigator.pop(context);
          _showSnack('✅ Rent request sent to owner!', color: Colors.green);
          _loadData();
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  Future<void> _payMonthlyRent() async {
    final rentWei = _propertyData!['monthlyRent'] as BigInt;
    _showProcessingDialog('Paying monthly rent…');
    try {
      final txHash = await _blockchainService.payLandMonthlyRent(
        propertyId: widget.propertyId,
        amount: rentWei,
      );
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (mounted) Navigator.pop(context);
        if (ok) {
          _showSnack('✅ Rent paid successfully!', color: Colors.green);
          _loadData();
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content        : Text(msg, style: GoogleFonts.poppins()),
      backgroundColor: color ?? AppTheme.primaryStart,
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showProcessingDialog(String label) {
    showDialog(
      context           : context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding   : const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color       : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children    : [
              const CircularProgressIndicator(color: AppTheme.primaryStart),
              const SizedBox(height: 18),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color     : AppTheme.textPrimary)),
              const SizedBox(height: 6),
              Text('Please wait…',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Loading
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.primaryGradient,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text('Loading rent data…',
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    // Error
    if (_propertyData == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _buildAppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text('Failed to load property data',
                  style: GoogleFonts.poppins(
                      color: AppTheme.textSecondary, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    final totalFractions  = _propertyData!['totalFractions'] as int;
    final ownershipPct    = totalFractions > 0
        ? (_userFractions / totalFractions * 100)
        : 0.0;
    final hasRent = _unclaimedRent > BigInt.zero;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // ── Gradient header ──
          _buildHeader(totalFractions, ownershipPct),

          // ── Scrollable body ──
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

                      // Property card
                      _buildPropertyCard(totalFractions, ownershipPct),
                      const SizedBox(height: 16),

                      // Unclaimed rent hero card
                      _buildRentHeroCard(hasRent),
                      const SizedBox(height: 16),

                      // Rental Listing / Request Section
                      _buildRentalSection(),
                      const SizedBox(height: 16),

                      // Distribute section (owner only)
                      if (widget.isOwner) ...[
                        _buildDistributeSection(),
                        const SizedBox(height: 16),
                      ],

                      // Info card
                      _buildInfoCard(ownershipPct),
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

  // ── Gradient header ───────────────────────────────────────────────────────
  Widget _buildHeader(int totalFractions, double ownershipPct) {
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
              // Back + title
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Rent Management',
                          style: GoogleFonts.poppins(
                            fontSize  : 18,
                            fontWeight: FontWeight.w700,
                            color     : Colors.white,
                          )),
                      Text(
                        widget.isOwner
                            ? 'Distribute & claim rent'
                            : 'Claim your rent share',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color   : Colors.white.withOpacity(0.8)),
                      ),
                    ],
                  ),
                  if (widget.isOwner) ...[
                    const Spacer(),
                    Container(
                      padding   : const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color       : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Owner',
                          style: GoogleFonts.poppins(
                            color     : Colors.white,
                            fontSize  : 11,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // Stats row
              Row(
                children: [
                  _HeaderStat(
                    icon : Icons.layers_rounded,
                    label: 'Your Fractions',
                    value: '$_userFractions',
                  ),
                  const SizedBox(width: 10),
                  _HeaderStat(
                    icon : Icons.pie_chart_rounded,
                    label: 'Ownership',
                    value: '${ownershipPct.toStringAsFixed(1)}%',
                  ),
                  const SizedBox(width: 10),
                  _HeaderStat(
                    icon : Icons.grid_view_rounded,
                    label: 'Total',
                    value: '${_propertyData!['totalFractions']}',
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
  Widget _buildPropertyCard(int totalFractions, double ownershipPct) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding   : const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color       : AppTheme.surface,
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
                    Text(_propertyData!['location'] ?? '—',
                        style: GoogleFonts.poppins(
                          fontSize  : 15,
                          fontWeight: FontWeight.w700,
                          color     : AppTheme.textPrimary,
                        )),
                    Text(
                      '${_propertyData!['city']}  •  '
                          '${_propertyData!['totalArea']} ${_propertyData!['areaUnit']}',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppTheme.primaryStart.withOpacity(0.1)),
          const SizedBox(height: 10),
          // Ownership bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your ownership share',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppTheme.textSecondary)),
              Text('${ownershipPct.toStringAsFixed(2)}%',
                  style: GoogleFonts.poppins(
                    fontSize  : 12,
                    fontWeight: FontWeight.w700,
                    color     : AppTheme.primaryStart,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value          : totalFractions > 0
                  ? _userFractions / totalFractions
                  : 0,
              minHeight      : 8,
              backgroundColor: AppTheme.surface,
              valueColor     :
              const AlwaysStoppedAnimation<Color>(AppTheme.primaryStart),
            ),
          ),
        ],
      ),
    );
  }

  // ── Rent hero card ────────────────────────────────────────────────────────
  Widget _buildRentHeroCard(bool hasRent) {
    return Container(
      width    : double.infinity,
      padding  : const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasRent
              ? [const Color(0xFF1B6B3A), const Color(0xFF2ECC71)]
              : [AppTheme.primaryStartDark, AppTheme.primaryStart],
          begin: Alignment.topLeft,
          end  : Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color     : (hasRent ? Colors.green : AppTheme.primaryStart).withOpacity(0.3),
            blurRadius: 16,
            offset    : const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding   : const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 14),
          Text('Unclaimed Rent',
              style: GoogleFonts.poppins(
                  color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            '${_blockchainService.weiToEther(_unclaimedRent)} MATIC',
            style: GoogleFonts.poppins(
              color     : Colors.white,
              fontSize  : 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),

          // Claim button
                  ClaimRentButton(
                    onPressed: _claimRent,
                    isLoading: false, // Could add loading state
                  ),
        ],
      ),
    );
  }

  // ── Distribute section ────────────────────────────────────────────────────
  Widget _buildDistributeSection() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding   : const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color       : AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.upload_rounded,
                    color: AppTheme.primaryStart, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distribute Rent',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize  : 15,
                        color     : AppTheme.textPrimary,
                      )),
                  Text('Send rent to all fraction holders',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: AppTheme.primaryStart.withOpacity(0.1)),
          const SizedBox(height: 14),

          // Amount field
          Container(
            decoration: BoxDecoration(
              color       : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border      : Border.all(color: AppTheme.primaryStart.withOpacity(0.2)),
              boxShadow   : [
                BoxShadow(
                  color     : AppTheme.primaryStart.withOpacity(0.05),
                  blurRadius: 8,
                  offset    : const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller  : _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              style       : GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color     : AppTheme.textPrimary),
              decoration  : InputDecoration(
                hintText      : 'Enter amount to distribute',
                hintStyle     : GoogleFonts.poppins(
                    color: AppTheme.textSecondary.withOpacity(0.6),
                    fontSize: 14),
                prefixIcon    : const Icon(
                    Icons.monetization_on_rounded, color: AppTheme.primaryStart),
                suffixText    : 'MATIC',
                suffixStyle   : GoogleFonts.poppins(
                    color     : AppTheme.primaryStart,
                    fontWeight: FontWeight.w700),
                border        : InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Distribute button
          _GradientButton(
            label    : 'Distribute Rent',
            icon     : Icons.upload_rounded,
            onPressed: _distributeRent,
          ),
          const SizedBox(height: 10),

          Center(
            child: Text(
              'Rent is distributed proportionally to all fraction holders.',
              textAlign: TextAlign.center,
              style    : GoogleFonts.poppins(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Rental Section ────────────────────────────────────────────────────────
  Widget _buildRentalSection() {
    final bool isForRent = _propertyData!['isForRent'] ?? false;
    final BigInt monthlyRent = _propertyData!['monthlyRent'] ?? BigInt.zero;
    final String currentTenant = _propertyData!['currentTenant'] ?? '0x0000000000000000000000000000000000000000';
    final String pendingTenant = _propertyData!['pendingTenant'] ?? '0x0000000000000000000000000000000000000000';
    final bool hasTenant = currentTenant != '0x0000000000000000000000000000000000000000';
    final bool hasPending = pendingTenant != '0x0000000000000000000000000000000000000000';
    
    final userAddr = _blockchainService.connectedAddress?.toLowerCase() ?? '';
    final bool isTenant = currentTenant.toLowerCase() == userAddr;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.vpn_key_rounded, color: AppTheme.primaryStart, size: 22),
              ),
              const SizedBox(width: 12),
              Text('Rental Status',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  )),
            ],
          ),
          const SizedBox(height: 16),
          
          if (widget.isOwner) ...[
            if (!isForRent && !hasTenant) ...[
              Text('Property is not yet listed for rent.',
                  style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              _buildRentInputField(),
              const SizedBox(height: 12),
              ListForRentButton(onPressed: _listForRent),
            ] else if (isForRent && !hasPending) ...[
              _buildStatusRow('Status', 'Available for Rent', Colors.green),
              _buildStatusRow('Monthly Rent', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
              const SizedBox(height: 12),
              const Center(child: Text('Waiting for tenants…', style: TextStyle(fontSize: 12, color: Colors.grey))),
            ] else if (hasPending) ...[
              _buildStatusRow('Status', 'Pending Request', Colors.orange),
              _buildStatusRow('Tenant Address', pendingTenant, AppTheme.textPrimary),
              const SizedBox(height: 12),
              AcceptRentRequestButton(onPressed: _acceptRentRequest),
            ] else if (hasTenant) ...[
              _buildStatusRow('Status', 'Rented', AppTheme.primaryStart),
              _buildStatusRow('Current Tenant', currentTenant, AppTheme.textPrimary),
              _buildStatusRow('Monthly Income', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
            ],
          ] else ...[
            // Non-owner view
            if (isTenant) ...[
              _buildStatusRow('Status', 'You are the Tenant', AppTheme.primaryStart),
              _buildStatusRow('Monthly Rent', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
              const SizedBox(height: 16),
              PayRentButton(onPressed: _payMonthlyRent),
            ] else if (isForRent) ...[
              _buildStatusRow('Status', 'Available for Rent', Colors.green),
              _buildStatusRow('Monthly Rent', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
              const SizedBox(height: 16),
              _GradientButton(
                label: 'Request to Rent',
                icon: Icons.send_rounded,
                onPressed: _requestRent,
              ),
            ] else if (hasTenant) ...[
              _buildStatusRow('Status', 'Already Rented', Colors.grey),
            ] else ...[
              _buildStatusRow('Status', 'Not for Rent', Colors.grey),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRentInputField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryStart.withOpacity(0.2)),
      ),
      child: TextField(
        controller: _rentPriceCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Enter monthly rent amount',
          prefixIcon: const Icon(Icons.monetization_on_rounded, color: AppTheme.primaryStart),
          suffixText: 'MATIC',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
          Flexible(
            child: Text(value,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _claimRent() async {
    _showProcessingDialog('Claiming your rent share…');
    try {
      final txHash = await _blockchainService.claimLandRent(widget.propertyId);
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (mounted) Navigator.pop(context);
        if (ok) {
          _showSnack('✅ Rent claimed successfully!', color: Colors.green);
          _loadData();
        } else {
          _showSnack('❌ Claim failed on blockchain', color: Colors.red);
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  Future<void> _acceptRentRequest() async {
    _showProcessingDialog('Accepting tenant…');
    try {
      final txHash = await _blockchainService.acceptLandRentRequest(widget.propertyId);
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (ok) {
          // Update Firestore: find the pending request and mark as approved
          final q = await _db.collection('rent_requests')
              .where('assetId', isEqualTo: widget.assetId)
              .where('status', isEqualTo: 'pending')
              .limit(1).get();
          
          if (q.docs.isNotEmpty) {
            final batch = _db.batch();
            batch.update(q.docs.first.reference, {'status': 'approved'});
            batch.update(_db.collection('transactions').doc(q.docs.first.id), {'status': 'approved'});
            
            // Update asset doc
            batch.update(_db.collection('assets').doc(widget.assetId), {
              'isForRent': false,
              'currentTenant': q.docs.first.data()['tenantUid'],
              'currentTenantAddress': _propertyData!['pendingTenant'],
            });
            
            await batch.commit();
          }

          if (mounted) Navigator.pop(context);
          _showSnack('✅ Tenant accepted!', color: Colors.green);
          _loadData();
        }
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  // ── Info card ─────────────────────────────────────────────────────────────
  Widget _buildInfoCard(double ownershipPct) {
    final bullets = [
      'Rent is distributed proportionally based on fraction ownership',
      'You can claim your share at any time',
      'All transactions are recorded on the blockchain',
      'Your share: ${ownershipPct.toStringAsFixed(2)}% of total rent',
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding   : const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color       : AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.info_outline_rounded,
                    color: AppTheme.primaryStart, size: 20),
              ),
              const SizedBox(width: 10),
              Text('How Rent Distribution Works',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize  : 14,
                    color     : AppTheme.textPrimary,
                  )),
            ],
          ),
          const SizedBox(height: 14),
          ...bullets.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child  : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children          : [
                Container(
                  margin    : const EdgeInsets.only(top: 5),
                  width     : 6,
                  height    : 6,
                  decoration: const BoxDecoration(
                      color: AppTheme.primaryStart, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(b,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          color   : AppTheme.textSecondary,
                          height  : 1.4)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: AppTheme.primaryStart,
    flexibleSpace  : Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
      ),
    ),
    leading: IconButton(
      icon     : const Icon(Icons.arrow_back_ios_new_rounded,
          color: Colors.white, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    title: Text('Rent Management',
        style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700, color: Colors.white)),
  );
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding   : const EdgeInsets.all(18),
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
  final IconData icon;
  final String   label;
  final String   value;
  const _HeaderStat(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding   : const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
                  color: Colors.white70, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _GradientButton extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final VoidCallback onPressed;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Container(
    height    : 52,
    decoration: BoxDecoration(
      gradient    : LinearGradient(
        colors: [AppTheme.primaryStartDark, AppTheme.primaryStart],
        begin : Alignment.topLeft,
        end   : Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow   : [
        BoxShadow(
          color     : AppTheme.primaryStart.withOpacity(0.35),
          blurRadius: 12,
          offset    : const Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color       : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child       : InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap       : onPressed,
        child       : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children         : [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(label,
                style: GoogleFonts.poppins(
                  color     : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize  : 15,
                )),
          ],
        ),
      ),
    ),
  );
}