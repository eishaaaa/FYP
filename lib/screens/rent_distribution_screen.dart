// lib/screens/rent_distribution_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../blockchain/blockchain_service.dart';
import 'package:digitalgoods/services/chat_services.dart';
import '../theme.dart';
import '../widgets/rent_actions.dart';

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
  final _depositCtrl       = TextEditingController();
  final _leaseMonthsCtrl   = TextEditingController(text: '6');
  final _db                = FirebaseFirestore.instance;
  final _auth              = FirebaseAuth.instance;

  Map<String, dynamic>? _propertyData;
  Map<String, dynamic>? _currentTransaction;
  BigInt _unclaimedRent = BigInt.zero;
  int    _userFractions = 0;
  int    _escrowFractions = 0;
  bool   _isMasterOwner = false;
  bool   _loading       = true;
  bool   _processing    = false;
  int?   _activePropertyId;
  String? _errorMessage;

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
    _depositCtrl.dispose();
    _leaseMonthsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      await _blockchainService.init();
      
      int currentId = widget.propertyId;
      _activePropertyId = currentId;
      var property = await _blockchainService.getLandProperty(currentId);

      if (property == null) {
        if (currentId > 0) {
            final fallback = await _blockchainService.getLandProperty(currentId - 1);
            if (fallback != null && await _isMatch(fallback)) {
              await _db.collection('assets').doc(widget.assetId).update({'blockchainTokenId': currentId - 1});
              property = fallback;
              _activePropertyId = currentId - 1;
            }
        }
        if (property == null) {
            final fallback = await _blockchainService.getLandProperty(currentId + 1);
            if (fallback != null && await _isMatch(fallback)) {
              await _db.collection('assets').doc(widget.assetId).update({'blockchainTokenId': currentId + 1});
              property = fallback;
              _activePropertyId = currentId + 1;
            }
        }
      }
      currentId = _activePropertyId!;
      
      if (property != null) {
        await _blockchainService.verifyAndHealAsset(
          type: 'land',
          blockchainId: currentId,
          firestoreDocId: widget.assetId,
          firestore: _db,
        );
      }

      final addr = _blockchainService.connectedAddress;
      final assetDocTask = _db.collection('assets').doc(widget.assetId).get();
      
      if (addr != null && property != null) {
        final results = await Future.wait([
          _blockchainService.getUnclaimedRent(addr, currentId),
          _blockchainService.getUserFractions(addr, currentId),
          _blockchainService.getEscrowBalance(currentId),
          assetDocTask,
        ]);
        
        _unclaimedRent = results[0] as BigInt;
        _userFractions = results[1] as int;
        _escrowFractions = results[2] as int;
        final assetDoc = results[3] as DocumentSnapshot;
        _finishLoading(property, assetDoc, addr);
      } else {
        final assetDoc = await assetDocTask;
        _finishLoading(property, assetDoc, addr);
      }
      // 🔎 Fetch current transaction status from DB
      final txQuery = await _db.collection('transactions')
          .where('assetId', isEqualTo: widget.assetId)
          .where('status', whereIn: ['pendingApproval', 'approved', 'active', 'recallPending'])
          .limit(1).get();
      
      _currentTransaction = txQuery.docs.isNotEmpty ? txQuery.docs.first.data() : null;
      if (_currentTransaction != null) {
        _currentTransaction!['id'] = txQuery.docs.first.id;
        
        // ⏰ Auto-Finalize if Expired
        if (_currentTransaction!['status'] == 'active') {
          final expiryTs = _currentTransaction!['expiryDate'] as Timestamp?;
          if (expiryTs != null && expiryTs.toDate().isBefore(DateTime.now())) {
            debugPrint("Rental expired! Finalizing...");
            await _blockchainService.finalizeTransaction(_currentTransaction!['id']);
            await _loadData(); // Reload after finalization
            return;
          }
        }
      }

      if (mounted) {
        setState(() {
          _errorMessage = null;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("LoadError: $e");
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _finishLoading(Map<String, dynamic>? property, DocumentSnapshot assetDoc, String? addr) {
    final assetData = assetDoc.data() as Map<String, dynamic>?;
    final ownerUid = assetData?['ownerId'] ?? assetData?['ownerUid'];
    final currentAddress = addr?.toLowerCase();
    final chainOwner     = property?['originalOwner']?.toString().toLowerCase();
    
    _isMasterOwner = (_auth.currentUser?.uid == ownerUid) || 
                     (currentAddress != null && currentAddress == chainOwner);
    
    if (_isMasterOwner && _userFractions == 0) {
      final totalF = property?['totalFractions'] as int? ?? 100;
      _userFractions = totalF - _escrowFractions;
    }

    if (mounted) {
      // VITAL: Self-healing for Marketplace visibility
      if (assetData != null && (assetData['category'] != 'land' || assetData['isMinted'] != true)) {
        _db.collection('assets').doc(widget.assetId).update({
          'category': 'land',
          'isMinted': true,
        });
        _showSnack('🛠️ Optimized for Marketplace', color: Colors.blue);
      }

      setState(() {
        if (property != null) {
          _propertyData = Map<String, dynamic>.from(property);
          _propertyData!['originalOwnerUid'] = ownerUid;
          _propertyData!['securityDeposit'] = assetData?['securityDeposit'] ?? 0.0;
          _propertyData!['disputeActive'] = assetData?['disputeActive'] ?? false;
          _propertyData!['disputeReason'] = assetData?['disputeReason'] ?? '';
        } else {
          _errorMessage = "Property data not found on blockchain.";
        }
        _loading = false;
      });
    }
  }

  Future<bool> _isMatch(Map<String, dynamic> chainData) async {
    final assetDoc = await _db.collection('assets').doc(widget.assetId).get();
    final fsTitle = assetDoc.data()?['title']?.toString().toLowerCase() ?? '';
    final chainTitle = chainData['location']?.toString().toLowerCase() ?? '';
    return fsTitle.contains(chainTitle) || chainTitle.contains(fsTitle);
  }

  bool _checkBlockchainOwnership() {
    final currentAddress = _blockchainService.connectedAddress?.toLowerCase();
    final chainOwner = _propertyData?['originalOwner']?.toString().toLowerCase();
    
    if (currentAddress == null || currentAddress != chainOwner) {
      _showSnack(
        '❌ Wallet Mismatch\n\n'
        'This action requires the owner wallet ($chainOwner).\n'
        'You are currently using: ${currentAddress ?? "None"}',
        color: Colors.red,
      );
      return false;
    }
    return true;
  }

  Future<void> _distributeRent() async {
    if (!_checkBlockchainOwnership()) return;
    
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      _showSnack('Please enter a valid amount');
      return;
    }
    final weiAmount = _blockchainService.etherToWei(amount);
    _showProcessingDialog('Distributing rent…');
    try {
      final txHash = await _blockchainService.distributeLandRent(
        propertyId: _activePropertyId ?? widget.propertyId,
        amount    : weiAmount,
      );
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (mounted) Navigator.pop(context);
        if (ok) {
          _showSnack('✅ Rent distributed successfully!', color: Colors.green);
          _amountCtrl.clear();
          _loadData();
        }
      } else {
        if (mounted) Navigator.pop(context);
        _showSnack('❌ Transaction failed.');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  Future<void> _listForRent() async {
    if (!_checkBlockchainOwnership()) return;

    final rentAmount = double.tryParse(_rentPriceCtrl.text);
    final depositAmount = double.tryParse(_depositCtrl.text) ?? 0.0;
    final leaseMonths = int.tryParse(_leaseMonthsCtrl.text) ?? 6;

    if (rentAmount == null || rentAmount <= 0) {
      _showSnack('Please enter a valid monthly rent');
      return;
    }
    
    setState(() => _processing = true);
    // Convert PKR to MATIC for blockchain
    final maticAmount = rentAmount / 200.0;
    final weiRent = _blockchainService.etherToWei(maticAmount);
    _showProcessingDialog('Signature Required\nPlease check your wallet app.');
    
    try {
      final txHash = await _blockchainService.listLandForRent(
        propertyId: _activePropertyId ?? widget.propertyId,
        rentAmount: weiRent,
      );
      
      if (txHash != null) {
        if (mounted) Navigator.pop(context);
        _showSnack('⏳ Waiting for blockchain confirmation...', color: Colors.orange);

        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (ok) {
          await _db.collection('assets').doc(widget.assetId).update({
            'isForRent': true,
            'monthlyRent': rentAmount,
            'securityDeposit': depositAmount,
            'leaseMonths': leaseMonths,
            'currentTenant': null,
            'currentTenantAddress': null,
            'pendingTenant': null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          
          if (mounted) {
            _showSnack('✅ Rental listing confirmed!', color: Colors.green);
            _loadData();
          }
        } else {
          if (mounted) _showSnack('❌ Transaction failed.', color: Colors.red);
        }
      } else {
        if (mounted) Navigator.pop(context);
        _showSnack('❌ Failed to initiate transaction.', color: Colors.red);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _claimRent() async {
    _showProcessingDialog('Claiming your rent share…');
    try {
      final txHash = await _blockchainService.claimLandRent(_activePropertyId ?? widget.propertyId);
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

  Future<void> _requestRent() async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    _showProcessingDialog('Sending rent request…');
    try {
      final txHash = await _blockchainService.requestLandRent(_activePropertyId ?? widget.propertyId);
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (ok) {
          final txId = _db.collection('transactions').doc().id;
          final batch = _db.batch();
          final rentAmount = _blockchainService.weiToEther(_propertyData!['monthlyRent']);
          final ownerUid = _propertyData!['originalOwnerUid'] ?? '';
          final deposit = (double.tryParse(_propertyData!['securityDeposit']?.toString() ?? '0') ?? 0.0);

          batch.set(_db.collection('transactions').doc(txId), {
            'transactionId': txId,
            'assetId': widget.assetId,
            'buyerUid': user.uid,
            'sellerUid': ownerUid,
            'status': 'pendingApproval',
            'category': 'land',
            'requestType': 'rental',
            'amount': rentAmount,
            'rentalFee': double.tryParse(rentAmount) ?? 0.0,
            'depositAmount': deposit,
            'blockchainPropertyId': _activePropertyId ?? widget.propertyId,
            'blockchainTokenId': _activePropertyId ?? widget.propertyId,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Create Locked Chat
          batch.set(_db.collection('chats').doc(txId), {
            'transactionId': txId,
            'assetId': widget.assetId,
            'assetType': 'land',
            'buyerUid': user.uid,
            'sellerUid': ownerUid,
            'participants': [user.uid, ownerUid],
            'lastMessage': 'I am interested in renting this property.',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'isLocked': true, // 🔒 Gated until approval
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
    final monthlyRentWei = _propertyData!['monthlyRent'] as BigInt;
    final depositMatic = double.tryParse(_currentTransaction?['depositAmount']?.toString() ?? '0') ?? 0.0;
    final depositWei = _blockchainService.etherToWei(depositMatic);
    
    final isInitialPayment = _currentTransaction?['status'] == 'approved';
    final totalWei = isInitialPayment ? (monthlyRentWei + depositWei) : monthlyRentWei;

    _showProcessingDialog(isInitialPayment ? 'Paying Rent & Deposit…' : 'Paying monthly rent…');
    try {
      final txHash = await _blockchainService.payLandMonthlyRent(
        propertyId: _activePropertyId ?? widget.propertyId,
        amount: totalWei,
      );
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (mounted) Navigator.pop(context);
        if (ok) {
          // 🔎 Find the active transaction to activate the rental state machine
          final q = await _db.collection('transactions')
              .where('assetId', isEqualTo: widget.assetId)
              .where('status', whereIn: ['approved', 'active'])
              .limit(1).get();
          
          if (q.docs.isNotEmpty) {
            final txId = q.docs.first.id;
            await _blockchainService.activateRental(txId);
            _showSnack('✅ Rent paid & Rental Activated!', color: Colors.green);
          } else {
            _showSnack('✅ Rent paid successfully!', color: Colors.green);
          }
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

  Future<void> _recallAsset() async {
    _showProcessingDialog('Initiating recall…');
    try {
      // Find the active transaction
      final q = await _db.collection('transactions')
          .where('assetId', isEqualTo: widget.assetId)
          .where('status', isEqualTo: 'active')
          .limit(1).get();
      
      if (q.docs.isEmpty) {
        if (mounted) Navigator.pop(context);
        _showSnack('No active rental transaction found.');
        return;
      }

      final txId = q.docs.first.id;
      await _blockchainService.recallAsset(txId);
      
      if (mounted) Navigator.pop(context);
      _showSnack('🚨 Asset recalled successfully!', color: Colors.orange);
      _loadData();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Recall error: $e', color: Colors.red);
    }
  }

  Future<void> _acceptRentRequest() async {
    _showProcessingDialog('Accepting tenant…');
    try {
      final txHash = await _blockchainService.acceptLandRentRequest(_activePropertyId ?? widget.propertyId);
      if (txHash != null) {
        final ok = await _blockchainService.waitForConfirmation(txHash);
        if (ok) {
          // Find the transaction record in DB
          final q = await _db.collection('transactions')
              .where('assetId', isEqualTo: widget.assetId)
              .where('status', isEqualTo: 'pendingApproval')
              .where('requestType', isEqualTo: 'rental')
              .limit(1).get();
          
          if (q.docs.isNotEmpty) {
            final batch = _db.batch();
            final txId = q.docs.first.id;
            final tData = q.docs.first.data();
            final tenantUid = tData['buyerUid'];

            batch.update(q.docs.first.reference, {'status': 'approved'});
            
            // 🔓 Unlock Chat Channel
            batch.update(_db.collection('chats').doc(txId), {'isLocked': false});
            
            // 💬 Send notification message
            await ChatService.sendMessage(
              chatId: txId, 
              text: 'Rental request approved! You can now proceed with payment and activation.',
              receiverId: tenantUid,
            );
            
            batch.update(_db.collection('assets').doc(widget.assetId), {
              'isForRent': false,
              'currentTenant': tenantUid,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Loading rent data…', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    if (_propertyData == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: _buildAppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Failed to load property data',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: AppTheme.textSecondary, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    final totalFractions  = _propertyData!['totalFractions'] as int;
    final ownershipPct    = (_isMasterOwner && _userFractions == 0 && _escrowFractions == 0)
        ? 100.0
        : (totalFractions > 0)
            ? ((_userFractions + _escrowFractions) / totalFractions * 100).clamp(0, 100).toDouble()
            : 0.0;
    final hasRent = _unclaimedRent > BigInt.zero;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(totalFractions, ownershipPct),
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
                      _buildPropertyCard(totalFractions, ownershipPct),
                      const SizedBox(height: 16),
                      _buildRentHeroCard(hasRent),
                      const SizedBox(height: 16),
                      _buildRentalSection(),
                      const SizedBox(height: 16),
                      if (widget.isOwner) ...[
                        _buildDistributeSection(),
                        const SizedBox(height: 16),
                      ],
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

  Widget _buildHeader(int totalFractions, double ownershipPct) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [AppTheme.primaryStartDark, AppTheme.primaryStart],
            begin : Alignment.topLeft,
            end   : Alignment.bottomRight),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child : Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child  : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rent Management', 
                             style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                             overflow: TextOverflow.ellipsis),
                        Text(widget.isOwner ? 'Distribute & claim rent' : 'Claim your rent share',
                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withOpacity(0.8)),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Actions wrapped to prevent overflow
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isOwner) ...[
                        _HeaderIconButton(icon: Icons.refresh_rounded, onTap: _loadData),
                        const SizedBox(width: 6),
                        _HeaderIconButton(icon: Icons.help_outline_rounded, onTap: _showHowItWorks),
                        const SizedBox(width: 6),
                        _WalletStatusBadge(
                          isCorrect: _blockchainService.connectedAddress?.toLowerCase() == _propertyData?['originalOwner']?.toString().toLowerCase(),
                          onTap: () async {
                            await _blockchainService.connectWallet(context);
                            _loadData();
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing   : 8,
                runSpacing: 8,
                children: [
                  _HeaderStat(icon: Icons.layers_rounded, label: _isMasterOwner ? 'Managed' : 'Yours', value: _isMasterOwner ? '${_userFractions + _escrowFractions}' : '$_userFractions'),
                  _HeaderStat(icon: Icons.pie_chart_rounded, label: 'Ownership', value: '${ownershipPct.toStringAsFixed(1)}%'),
                  _HeaderStat(icon: Icons.shopping_bag_rounded, label: 'Escrow', value: '$_escrowFractions'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPropertyCard(int totalFractions, double ownershipPct) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.location_on_rounded, color: AppTheme.primaryStart, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_propertyData!['location'] ?? '—', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    Text('${_propertyData!['city']}  •  ${_propertyData!['totalArea']} ${_propertyData!['areaUnit']}',
                        style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppTheme.primaryStart.withOpacity(0.1)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your ownership share', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
              Text('${ownershipPct.toStringAsFixed(2)}%', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryStart)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: totalFractions > 0 ? _userFractions / totalFractions : 0,
              minHeight: 8,
              backgroundColor: AppTheme.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryStart),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRentHeroCard(bool hasRent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasRent ? [const Color(0xFF1B6B3A), const Color(0xFF2ECC71)] : [AppTheme.primaryStartDark, AppTheme.primaryStart],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: (hasRent ? Colors.green : AppTheme.primaryStart).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 14),
          Text('Unclaimed Rent', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 6),
          Text('${_blockchainService.weiToEther(_unclaimedRent)} MATIC',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          ClaimRentButton(onPressed: _claimRent, isLoading: false),
        ],
      ),
    );
  }

  Widget _buildRentalSection() {
    final bool isForRent = _propertyData!['isForRent'] ?? false;
    final BigInt monthlyRent = _propertyData!['monthlyRent'] ?? BigInt.zero;
    final String currentTenant = _propertyData!['currentTenant'] ?? '0x0000000000000000000000000000000000000000';
    final String pendingTenant = _propertyData!['pendingTenant'] ?? '0x0000000000000000000000000000000000000000';
    final bool hasTenant = currentTenant != '0x0000000000000000000000000000000000000000';
    final bool hasPending = pendingTenant != '0x0000000000000000000000000000000000000000';
    final userAddr = _blockchainService.connectedAddress?.toLowerCase() ?? '';
    final bool isTenant = currentTenant.toLowerCase() == userAddr;
    
    final dbStatus = _currentTransaction?['status'];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.vpn_key_rounded, color: AppTheme.primaryStart, size: 22),
              ),
              const SizedBox(width: 12),
              Text('Rental Status', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          if (!_blockchainService.isConnected) ...[
            _buildConnectWalletPrompt(),
            const SizedBox(height: 16),
          ],
          if (widget.isOwner) ...[
            if (!isForRent && !hasTenant && dbStatus == null) ...[
              _buildOwnerListForRentFlow(),
            ] else if (isForRent && !hasPending && dbStatus == null) ...[
              _buildStatusRow('Status', 'Available for Rent', Colors.green),
              _buildStatusRow('Monthly Rent', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
              if ((_propertyData!['securityDeposit'] ?? 0) > 0) _buildStatusRow('Security Deposit', '${_propertyData!['securityDeposit']} MATIC', Colors.orange),
              const SizedBox(height: 12),
              const Center(child: Text('Waiting for tenants…', style: TextStyle(fontSize: 12, color: Colors.grey))),
            ] else if (dbStatus == 'pendingApproval') ...[
              _buildStatusRow('Status', 'Pending Approval', Colors.orange),
              _buildStatusRow('Tenant Address', pendingTenant, AppTheme.textPrimary),
              const SizedBox(height: 12),
              AcceptRentRequestButton(onPressed: _acceptRentRequest),
            ] else if (dbStatus == 'approved') ...[
              _buildStatusRow('Status', 'Approved - Waiting for Payment', AppTheme.primaryStart),
              _buildStatusRow('Tenant', _currentTransaction?['buyerUid'] ?? '—', AppTheme.textMid),
            ] else if (hasTenant || dbStatus == 'active') ...[
              _buildRentedView(currentTenant, monthlyRent),
            ],
          ] else ...[
            if (dbStatus == 'active' || isTenant) ...[
              _buildTenantView(monthlyRent),
            ] else if (dbStatus == 'pendingApproval') ...[
              _buildStatusRow('Status', 'Request Sent (Pending Approval)', Colors.orange),
            ] else if (dbStatus == 'approved') ...[
              _buildStatusRow('Status', 'Request Approved!', Colors.green),
              const SizedBox(height: 12),
              PayRentButton(onPressed: _payMonthlyRent),
            ] else if (isForRent) ...[
              _buildAvailableForRentView(monthlyRent),
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

  Widget _buildOwnerListForRentFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Property is not yet listed for rent.', style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 16),
        _buildTextField(_rentPriceCtrl, 'Monthly Rent (PKR)', Icons.money_rounded, isNumeric: true, suffix: 'PKR'),
        const SizedBox(height: 8),
        _buildConversionHint(_rentPriceCtrl.text),
        const SizedBox(height: 16),
        _buildTextField(_depositCtrl, 'Security Deposit (PKR)', Icons.security_rounded, isNumeric: true, suffix: 'PKR'),
        const SizedBox(height: 8),
        _buildConversionHint(_depositCtrl.text),
        const SizedBox(height: 16),
        _buildTextField(_leaseMonthsCtrl, 'Lease Duration (Months)', Icons.timer_rounded, isNumeric: true, suffix: 'Months'),
        const SizedBox(height: 24),
        ListForRentButton(onPressed: _processing ? null : _listForRent, isLoading: _processing),
      ],
    );
  }

  Widget _buildRentedView(String currentTenant, BigInt monthlyRent) {
    return Column(
      children: [
        _buildStatusRow('Status', 'Rented', AppTheme.primaryStart),
        _buildStatusRow('Current Tenant', currentTenant, AppTheme.textPrimary),
        _buildStatusRow('Monthly Income', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
        if ((_propertyData!['securityDeposit'] ?? 0) > 0) _buildStatusRow('Security Deposit Held', '${_propertyData!['securityDeposit']} MATIC', Colors.orange),
        
        // 💰 Pro-rata Refund Preview
        if (_currentTransaction != null && _currentTransaction!['status'] == 'active') ...[
          Builder(builder: (ctx) {
             final now = DateTime.now();
             final expiry = (_currentTransaction!['expiryDate'] as Timestamp?)?.toDate();
             final start = (_currentTransaction!['startDate'] as Timestamp?)?.toDate();
             if (expiry != null && start != null && expiry.isAfter(now)) {
                final total = expiry.difference(start).inSeconds;
                final remaining = expiry.difference(now).inSeconds;
                final fee = (_currentTransaction!['rentalFee'] ?? 0.0).toDouble();
                final refund = (fee * remaining / total).clamp(0, fee);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.withOpacity(0.2))),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate_outlined, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Est. Refund on Recall: ${refund.toStringAsFixed(4)} MATIC', style: GoogleFonts.poppins(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                );
             }
             return const SizedBox.shrink();
          }),
        ],

        const SizedBox(height: 16),
        if (!(_propertyData!['disputeActive'] ?? false))
          Row(
            children: [
              Expanded(child: RecallAssetButton(onPressed: _recallAsset)),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: () => _raiseDispute('Owner: Non-payment of rent'), icon: const Icon(Icons.warning_amber_rounded, size: 18), label: const Text('Raise Dispute'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)))),
            ],
          )
        else
          _buildDisputeBadge(),
      ],
    );
  }

  Widget _buildTenantView(BigInt monthlyRent) {
    return Column(
      children: [
        _buildStatusRow('Status', 'You are the Tenant', AppTheme.primaryStart),
        _buildStatusRow('Monthly Rent', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
        const SizedBox(height: 16),
        PayRentButton(onPressed: _payMonthlyRent),
        const SizedBox(height: 10),
        if (!(_propertyData!['disputeActive'] ?? false))
          OutlinedButton.icon(onPressed: () => _raiseDispute('Tenant: Deposit not being returned'), icon: const Icon(Icons.gavel_rounded, size: 18), label: const Text('Dispute: My Deposit'), style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), minimumSize: const Size.fromHeight(44)))
        else
          _buildDisputeBadge(),
      ],
    );
  }

  Widget _buildAvailableForRentView(BigInt monthlyRent) {
    return Column(
      children: [
        _buildStatusRow('Status', 'Available for Rent', Colors.green),
        _buildStatusRow('Monthly Rent', '${_blockchainService.weiToEther(monthlyRent)} MATIC', AppTheme.primaryStart),
        if ((_propertyData!['securityDeposit'] ?? 0) > 0) _buildStatusRow('Required Deposit', '${_propertyData!['securityDeposit']} MATIC', Colors.orange),
        const SizedBox(height: 16),
        RequestRentButton(onPressed: _requestRent),
      ],
    );
  }

  Widget _buildConnectWalletPrompt() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('Connect your wallet to manage rental status.', style: AppTheme.body(12, color: Colors.orange.shade800))),
          TextButton(onPressed: () async { await _blockchainService.connectWallet(context); _loadData(); }, child: const Text('Connect')),
        ],
      ),
    );
  }

  Widget _buildDistributeSection() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.upload_rounded, color: AppTheme.primaryStart, size: 22)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distribute Rent', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                  Text('Send rent to all fraction holders', style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRentInputField('Amount to distribute', _amountCtrl),
          const SizedBox(height: 16),
          _GradientButton(label: 'Distribute Rent', icon: Icons.upload_rounded, onPressed: _distributeRent),
          const SizedBox(height: 10),
          Center(child: Text('Rent is distributed proportionally to all holders.', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary))),
        ],
      ),
    );
  }

  Widget _buildInfoCard(double ownershipPct) {
    final bullets = [
      'Rent is distributed based on fraction ownership',
      'You can claim your share at any time',
      'All transactions are recorded on the blockchain',
      if (_escrowFractions > 0) 'Note: $_escrowFractions fractions are in escrow.',
      'Your share: ${ownershipPct.toStringAsFixed(2)}% of total rent',
    ];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.info_outline_rounded, color: AppTheme.primaryStart, size: 20)),
              const SizedBox(width: 10),
              Text('How Rent Distribution Works', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          ...bullets.map((b) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(margin: const EdgeInsets.only(top: 5), width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.primaryStart, shape: BoxShape.circle)), const SizedBox(width: 10), Expanded(child: Text(b, style: GoogleFonts.poppins(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)))]))),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: AppTheme.primaryStart,
    flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
    leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18), onPressed: () => Navigator.pop(context)),
    title: Text('Rent Management', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white)),
  );

  void _showSnack(String msg, {Color color = AppTheme.primaryStart}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  void _showProcessingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primaryStart),
            const SizedBox(height: 20),
            Text(message, textAlign: TextAlign.center, style: AppTheme.heading(14)),
            const SizedBox(height: 20),
            TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _processing = false); }, child: const Text('Cancel', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppTheme.textSecondary)),
          Flexible(child: Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildRentInputField(String hint, TextEditingController ctrl) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.primaryStart.withOpacity(0.2))),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.monetization_on_rounded, color: AppTheme.primaryStart), suffixText: 'MATIC', border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
      ),
    );
  }

  Widget _buildConversionHint(String pkrStr) {
    final pkr = double.tryParse(pkrStr) ?? 0;
    if (pkr <= 0) return const SizedBox.shrink();
    // 1 MATIC ≈ 200 PKR
    final matic = pkr / 200.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: AppTheme.primaryStart.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.currency_bitcoin_rounded, size: 14, color: AppTheme.primaryStart),
          const SizedBox(width: 6),
          Text('≈ ${matic.toStringAsFixed(4)} MATIC (at 200 PKR/MATIC)', 
               style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryStart)),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {bool isNumeric = false, String? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary.withOpacity(0.7))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primaryStart.withOpacity(0.1))),
          child: TextField(
            controller: ctrl,
            keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            onChanged: (v) => setState(() {}),
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppTheme.primaryStart, size: 20),
              suffixText: suffix,
              suffixStyle: GoogleFonts.poppins(color: Colors.grey, fontWeight: FontWeight.w600),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisputeBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.3))),
      child: Column(
        children: [
          Row(children: [const Icon(Icons.gavel_rounded, color: Colors.red, size: 20), const SizedBox(width: 10), Text('ACTIVE DISPUTE', style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 13))]),
          const SizedBox(height: 4),
          Text('Blockchain Admin notified. Funds locked.', style: GoogleFonts.poppins(color: Colors.red.withOpacity(0.8), fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _raiseDispute(String reason) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise Dispute?'),
        content: Text('This will flag the rental for Admin arbitration. $reason?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.collection('assets').doc(widget.assetId).update({'disputeActive': true, 'disputeReason': reason, 'disputeTimestamp': FieldValue.serverTimestamp()});
      
      if (_currentTransaction != null && _currentTransaction!['id'] != null) {
        await _blockchainService.disputeRental(_currentTransaction!['id'], reason);
      }
      
      _showSnack('⚖️ Dispute raised.', color: Colors.red);
      _loadData();
    }
  }

  Future<void> _releaseDeposit() async {
    _showProcessingDialog('Releasing deposit…');
    try {
      await _db.collection('assets').doc(widget.assetId).update({'currentTenant': null, 'currentTenantAddress': null, 'isForRent': true, 'disputeActive': false});
      if (mounted) Navigator.pop(context);
      _showSnack('✅ Deposit released.', color: Colors.green);
      _loadData();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnack('Error: $e', color: Colors.red);
    }
  }

  void _showHowItWorks() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('How it Works', style: AppTheme.heading(20)),
        content: const Text('Rent is distributed proportionally based on fractional ownership. Holders must claim their share manually.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it!'))],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: AppTheme.primaryStart.withOpacity(0.07), blurRadius: 14, offset: const Offset(0, 4))]), child: child);
}

class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _HeaderStat({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(width: 105, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(14)), child: Column(children: [Icon(icon, color: Colors.white70, size: 18), const SizedBox(height: 4), Text(value, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)), Text(label, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10), textAlign: TextAlign.center)]));
}

class _GradientButton extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final VoidCallback onPressed;
  const _GradientButton({required this.label, required this.icon, required this.onPressed});
  @override
  Widget build(BuildContext context) => Container(height: 52, decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.primaryStartDark, AppTheme.primaryStart], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: AppTheme.primaryStart.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))]), child: Material(color: Colors.transparent, borderRadius: BorderRadius.circular(14), child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onPressed, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 10), Text(label, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))]))));
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );
}

class _WalletStatusBadge extends StatelessWidget {
  final bool isCorrect;
  final VoidCallback onTap;
  const _WalletStatusBadge({required this.isCorrect, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isCorrect ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isCorrect ? Colors.green.withOpacity(0.4) : Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isCorrect ? Icons.account_balance_wallet_rounded : Icons.warning_amber_rounded, 
               color: isCorrect ? Colors.greenAccent : Colors.orangeAccent, size: 14),
          const SizedBox(width: 6),
          Text('Owner', style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );
}