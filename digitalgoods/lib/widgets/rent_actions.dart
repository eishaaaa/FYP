import 'package:flutter/material.dart';
import '../theme.dart';

class RentActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool isLoading;

  const RentActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      style: AppTheme.elevatedButtonStyle(background: color),
      icon: isLoading
          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Icon(icon, size: 18),
      label: Text(label, style: AppTheme.button(14)),
    );
  }
}

class ListForRentButton extends RentActionButton {
  const ListForRentButton({super.key, super.onPressed, super.isLoading})
      : super(label: "List for Rent", icon: Icons.add_business_rounded, color: AppTheme.accent);
}

class PayRentButton extends RentActionButton {
  const PayRentButton({super.key, super.onPressed, super.isLoading})
      : super(label: "Pay Monthly Rent", icon: Icons.payments_outlined, color: AppTheme.primaryStart);
}

class ClaimRentButton extends RentActionButton {
  const ClaimRentButton({super.key, super.onPressed, super.isLoading})
      : super(label: "Claim Rent Share", icon: Icons.account_balance_wallet_outlined, color: AppTheme.primaryStartDark);
}

class AcceptRentRequestButton extends RentActionButton {
  const AcceptRentRequestButton({super.key, super.onPressed, super.isLoading})
      : super(label: "Accept Tenant", icon: Icons.check_circle_outline, color: AppTheme.accent);
}

class ListForSaleButton extends RentActionButton {
  const ListForSaleButton({super.key, super.onPressed, super.isLoading})
      : super(label: "List for Sale", icon: Icons.sell_rounded, color: AppTheme.accent);
}

class BuyNowButton extends RentActionButton {
  const BuyNowButton({super.key, super.onPressed, super.isLoading})
      : super(label: "Buy Now", icon: Icons.shopping_cart_outlined, color: AppTheme.primaryStart);
}

class RecallAssetButton extends RentActionButton {
  const RecallAssetButton({super.key, super.onPressed, super.isLoading})
      : super(label: "Recall Asset", icon: Icons.keyboard_return_rounded, color: Colors.orange);
}

class RequestRentButton extends RentActionButton {
  const RequestRentButton({super.key, super.onPressed, super.isLoading})
      : super(label: "Request to Rent", icon: Icons.vpn_key_rounded, color: AppTheme.accent);
}
