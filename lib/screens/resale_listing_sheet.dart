// lib/screens/resale_listing_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/resale_service.dart';

const kDeepSea = Color(0xFF1F5562);
const kDeepSeaSoft = Color(0xFF2D6E7D);
const kMint = Color(0xFF5FB4AF);
const kMintSoft = Color(0xFFDFF2F0);
const kShell = Color(0xFFF7FAF9);
const kShellEdge = Color(0xFFEAF3F1);
const kPrimaryText = Color(0xFF172A32);
const kMutedText = Color(0xFF718B93);
const kCardShadow = Color(0xFF123840);
const kStar = Color(0xFFFFB648);

class ResaleListingSheet extends StatefulWidget {
  final String assetId;
  final Map<String, dynamic> assetData;

  const ResaleListingSheet({
    super.key,
    required this.assetId,
    required this.assetData,
  });

  static Future<bool> show(
      BuildContext context, {
        required String assetId,
        required Map<String, dynamic> assetData,
      }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ResaleListingSheet(assetId: assetId, assetData: assetData),
    );
    return result == true;
  }

  @override
  State<ResaleListingSheet> createState() => _ResaleListingSheetState();
}

class _ResaleListingSheetState extends State<ResaleListingSheet>
    with TickerProviderStateMixin {
  final _priceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _priceFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _resaleSvc = ResaleService();

  bool _submitting = false;
  bool _priceFocused = false;
  bool _descriptionFocused = false;
  num _parsedPrice = 0;

  late final AnimationController _sheetCtrl;
  late final Animation<double> _sheetFade;
  late final Animation<Offset> _sheetSlide;
  late final List<AnimationController> _sectionCtrls;
  late final List<Animation<double>> _sectionFades;
  late final List<Animation<Offset>> _sectionSlides;
  late final AnimationController _btnCtrl;
  late final Animation<double> _btnScale;

  static const double _platformFeeRate = 0.02;
  static const int _sectionCount = 7;

  num get _platformFee => _parsedPrice * _platformFeeRate;
  num get _netReceivable => _parsedPrice - _platformFee;

  @override
  void initState() {
    super.initState();
    _priceFocus.addListener(() {
      if (!mounted) return;
      setState(() => _priceFocused = _priceFocus.hasFocus);
    });
    _descriptionFocus.addListener(() {
      if (!mounted) return;
      setState(() => _descriptionFocused = _descriptionFocus.hasFocus);
    });

    _sheetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    _sheetFade = CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOut);
    _sheetSlide = Tween<Offset>(
      begin: const Offset(0, 0.14),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _sheetCtrl, curve: Curves.easeOutCubic));

    _sectionCtrls = List.generate(
      _sectionCount,
          (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 440),
      ),
    );
    _sectionFades = _sectionCtrls
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();
    _sectionSlides = _sectionCtrls
        .map(
          (c) => Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic)),
    )
        .toList();

    for (var i = 0; i < _sectionCount; i++) {
      Future.delayed(Duration(milliseconds: 140 + (i * 75)), () {
        if (mounted) _sectionCtrls[i].forward();
      });
    }

    _btnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _btnScale = Tween<double>(
      begin: 1,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    for (final ctrl in _sectionCtrls) {
      ctrl.dispose();
    }
    _btnCtrl.dispose();
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    _priceFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _onPriceChanged(String value) {
    setState(() => _parsedPrice = num.tryParse(value.replaceAll(',', '')) ?? 0);
  }

  Future<void> _confirm() async {
    final price = num.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null || price <= 0) {
      _showSnack('Please enter a valid price.', color: Colors.orange);
      return;
    }

    setState(() => _submitting = true);
    try {
      await _resaleSvc.listForResale(
        assetId: widget.assetId,
        price: price,
        description: _descriptionCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack('Failed to list: $e', color: Colors.red);
    }
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
        ),
        backgroundColor: color ?? kDeepSea,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _staggered(int index, Widget child) {
    return FadeTransition(
      opacity: _sectionFades[index],
      child: SlideTransition(position: _sectionSlides[index], child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imgList = widget.assetData['images'] as List?;
    final firstImg =
    (imgList != null && imgList.isNotEmpty && imgList.first is String)
        ? imgList.first as String
        : null;
    final title = widget.assetData['title'] as String? ?? 'Asset';
    final category = widget.assetData['category'] as String? ?? 'Digital asset';
    final location = widget.assetData['location'] as String?;
    final area = widget.assetData['area'] as String?;
    final rating = (widget.assetData['rating'] as num?)?.toDouble();
    final tokenId = widget.assetData['blockchainTokenId']?.toString() ?? 'N/A';
    final existingPrice = widget.assetData['resalePrice'] as num?;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return FadeTransition(
      opacity: _sheetFade,
      child: SlideTransition(
        position: _sheetSlide,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: const BoxDecoration(
              color: kShell,
              borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -60,
                  right: -30,
                  child: _softOrb(
                    size: 180,
                    colors: [
                      kMint.withOpacity(0.18),
                      kDeepSeaSoft.withOpacity(0.02),
                    ],
                  ),
                ),
                Positioned(
                  top: 120,
                  left: -70,
                  child: _softOrb(
                    size: 150,
                    colors: [kDeepSea.withOpacity(0.10), Colors.transparent],
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: kDeepSea.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _staggered(
                        0,
                        Column(
                          children: [
                            Row(
                              children: [
                                _IconShell(
                                  icon: Icons.chevron_left_rounded,
                                  onTap: _submitting
                                      ? null
                                      : () => Navigator.pop(context, false),
                                ),
                                Expanded(
                                  child: Text(
                                    'My Assets',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.sora(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: kPrimaryText,
                                    ),
                                  ),
                                ),
                                _IconShell(
                                  icon: Icons.more_horiz_rounded,
                                  onTap: () => _showSnack(
                                    'A 2% platform fee is deducted when the asset is listed.',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: kShellEdge),
                                      boxShadow: [
                                        BoxShadow(
                                          color: kCardShadow.withOpacity(0.05),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: kMintSoft,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.auto_awesome_rounded,
                                            color: kDeepSea,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Ready to list this asset',
                                                style: GoogleFonts.manrope(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: kPrimaryText,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Set a strong price and publish your resale card.',
                                                style: GoogleFonts.manrope(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: kMutedText,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [kDeepSea, kDeepSeaSoft],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: kDeepSea.withOpacity(0.22),
                                        blurRadius: 18,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.sell_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      _staggered(
                        1,
                        _buildAssetCard(
                          firstImg: firstImg,
                          title: title,
                          category: category,
                          location: location,
                          area: area,
                          rating: rating,
                          tokenId: tokenId,
                          existingPrice: existingPrice,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _staggered(
                        2,
                        _buildInputPanel(
                          title: 'Set your resale price',
                          subtitle:
                          'Buyers will see the full NFT transfer history for transparency.',
                          icon: Icons.payments_outlined,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _priceFocused ? kDeepSea : kShellEdge,
                                width: _priceFocused ? 1.5 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _priceFocused
                                      ? kDeepSea.withOpacity(0.12)
                                      : kCardShadow.withOpacity(0.04),
                                  blurRadius: _priceFocused ? 20 : 12,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'PKR',
                                  style: GoogleFonts.sora(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: kDeepSea,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: TextField(
                                    controller: _priceCtrl,
                                    focusNode: _priceFocus,
                                    keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[\d,.]'),
                                      ),
                                    ],
                                    onChanged: _onPriceChanged,
                                    style: GoogleFonts.sora(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: kPrimaryText,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '0',
                                      hintStyle: GoogleFonts.sora(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w600,
                                        color: kMutedText.withOpacity(0.45),
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: animation,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _parsedPrice > 0
                                      ? Container(
                                    key: const ValueKey('live'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kMintSoft,
                                      borderRadius: BorderRadius.circular(
                                        14,
                                      ),
                                    ),
                                    child: Text(
                                      'Live',
                                      style: GoogleFonts.manrope(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: kDeepSea,
                                      ),
                                    ),
                                  )
                                      : const SizedBox(key: ValueKey('empty')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _staggered(
                        3,
                        _buildInputPanel(
                          title: 'Tell buyers more',
                          subtitle:
                          'Add condition notes, perks, or transfer details to build trust.',
                          icon: Icons.edit_note_rounded,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _descriptionFocused
                                    ? kDeepSea
                                    : kShellEdge,
                                width: _descriptionFocused ? 1.5 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _descriptionFocused
                                      ? kDeepSea.withOpacity(0.10)
                                      : kCardShadow.withOpacity(0.04),
                                  blurRadius: _descriptionFocused ? 20 : 12,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _descriptionCtrl,
                              focusNode: _descriptionFocus,
                              keyboardType: TextInputType.multiline,
                              maxLines: 4,
                              maxLength: 500,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: kPrimaryText,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                'Describe the asset condition, utility, benefits, or anything that helps a buyer decide faster.',
                                hintStyle: GoogleFonts.manrope(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: kMutedText.withOpacity(0.7),
                                  height: 1.4,
                                ),
                                contentPadding: const EdgeInsets.fromLTRB(
                                  18,
                                  18,
                                  18,
                                  8,
                                ),
                                border: InputBorder.none,
                                counterStyle: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w700,
                                  color: kMutedText,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _staggered(4, _buildBreakdownCard()),
                      const SizedBox(height: 18),
                      _staggered(
                        5,
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF6F4),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: kMint.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.verified_user_rounded,
                                  color: kDeepSea,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Every resale stays transparent. Buyers can inspect transfer history and token ownership before they commit.',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: kDeepSea,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _staggered(
                        6,
                        Column(
                          children: [
                            ScaleTransition(
                              scale: _btnScale,
                              child: GestureDetector(
                                onTapDown: (_) {
                                  if (!_submitting) _btnCtrl.forward();
                                },
                                onTapCancel: () => _btnCtrl.reverse(),
                                onTapUp: (_) {
                                  _btnCtrl.reverse();
                                  if (!_submitting) _confirm();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                  width: double.infinity,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    gradient: _submitting
                                        ? null
                                        : const LinearGradient(
                                      colors: [kDeepSea, kMint],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    color: _submitting ? kMutedText : null,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: _submitting
                                        ? const []
                                        : [
                                      BoxShadow(
                                        color: kDeepSea.withOpacity(0.28),
                                        blurRadius: 22,
                                        offset: const Offset(0, 12),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      transitionBuilder: (child, animation) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: animation,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: _submitting
                                          ? const SizedBox(
                                        key: ValueKey('loading'),
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                          : Row(
                                        key: const ValueKey('label'),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.sell_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Resale',
                                            style: GoogleFonts.sora(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => Navigator.pop(context, false),
                              style: TextButton.styleFrom(
                                foregroundColor: kMutedText,
                                textStyle: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              child: const Text('Not now'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssetCard({
    required String? firstImg,
    required String title,
    required String category,
    required String tokenId,
    String? location,
    String? area,
    double? rating,
    num? existingPrice,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: kCardShadow.withOpacity(0.07),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: firstImg != null
                        ? Image.network(
                      firstImg,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    )
                        : _imagePlaceholder(),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(0.05),
                            Colors.black.withOpacity(0.30),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _cardBadge(
                      label: category.isEmpty ? 'Owned asset' : category,
                      icon: Icons.auto_graph_rounded,
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 14,
                    right: 14,
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _cardBadge(
                                label: 'NFT verified',
                                icon: Icons.verified_rounded,
                                dark: true,
                              ),
                              if (area != null && area.isNotEmpty)
                                _cardBadge(
                                  label: area,
                                  icon: Icons.grid_view_rounded,
                                  dark: true,
                                ),
                            ],
                          ),
                        ),
                        if (rating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: kStar,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: kPrimaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.sora(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: kPrimaryText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, color: kMint, size: 16),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    (location ?? category).trim().isEmpty
                        ? 'Digital collectible'
                        : (location ?? category),
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kMutedText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _parsedPrice > 0
                            ? 'Listing price'
                            : existingPrice != null
                            ? 'Current resale'
                            : 'Set your price',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kMutedText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.18),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _parsedPrice > 0
                              ? 'PKR ${_fmt(_parsedPrice)}'
                              : existingPrice != null
                              ? 'PKR ${_fmt(existingPrice)}'
                              : 'Add a value',
                          key: ValueKey('${_parsedPrice}_$existingPrice'),
                          style: GoogleFonts.sora(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: kPrimaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [kDeepSea, kDeepSeaSoft],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: kDeepSea.withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sell_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Resale',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip('Token #$tokenId'),
                _infoChip('2% platform fee'),
                _infoChip('Owner verified'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8F7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kShellEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: kDeepSea, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kPrimaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kMutedText,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    final keepRatio = _parsedPrice <= 0
        ? 0.98
        : (_netReceivable / _parsedPrice).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: kCardShadow.withOpacity(0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kDeepSea, kMint],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resale breakdown',
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kPrimaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A clean summary of what you keep after fees.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kMutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _amountRow(
            icon: Icons.sell_rounded,
            label: 'Asking price',
            value: _parsedPrice.toDouble(),
            accent: kDeepSea,
          ),
          _divider(),
          _amountRow(
            icon: Icons.percent_rounded,
            label: 'Platform fee (2%)',
            value: _platformFee.toDouble(),
            accent: Colors.orange.shade700,
            prefix: '- ',
          ),
          _divider(),
          _amountRow(
            icon: Icons.payments_rounded,
            label: 'You receive',
            value: _netReceivable.toDouble(),
            accent: Colors.green.shade700,
            emphasized: true,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 260),
              tween: Tween<double>(begin: 0, end: keepRatio),
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: kMintSoft,
                  valueColor: const AlwaysStoppedAnimation<Color>(kDeepSea),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You keep ${(keepRatio * 100).toStringAsFixed(0)}% of the sale after the platform fee.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: kMutedText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountRow({
    required IconData icon,
    required String label,
    required double value,
    required Color accent,
    bool emphasized = false,
    String prefix = '',
  }) {
    return Row(
      children: [
        Icon(icon, color: accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
              color: emphasized ? kPrimaryText : kMutedText,
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 240),
          tween: Tween<double>(begin: 0, end: value),
          builder: (context, animatedValue, _) {
            return Text(
              '${prefix}PKR ${_fmt(animatedValue)}',
              style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
                color: accent,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _divider() => Divider(height: 18, color: kShellEdge);

  Widget _softOrb({required double size, required List<Color> colors}) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  Widget _cardBadge({
    required String label,
    required IconData icon,
    bool dark = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? Colors.black.withOpacity(0.34)
            : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        border: dark ? Border.all(color: Colors.white.withOpacity(0.10)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: dark ? Colors.white : kDeepSea),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: dark ? Colors.white : kDeepSea,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kDeepSea,
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: kMintSoft,
      child: Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          size: 50,
          color: kDeepSea.withOpacity(0.35),
        ),
      ),
    );
  }

  String _fmt(num value) {
    if (value == 0) return '0';
    return value == value.truncate()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

class _IconShell extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _IconShell({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kShellEdge),
          ),
          child: Icon(icon, color: kPrimaryText, size: 22),
        ),
      ),
    );
  }
}
