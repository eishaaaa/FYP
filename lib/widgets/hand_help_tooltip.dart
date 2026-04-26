import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HandHelpTooltip extends StatefulWidget {
  final Widget child;
  final String message;
  final bool show;
  final Offset offset;

  const HandHelpTooltip({
    super.key,
    required this.child,
    required this.message,
    this.show = true,
    this.offset = const Offset(0, 0),
  });

  @override
  State<HandHelpTooltip> createState() => _HandHelpTooltipState();
}

class _HandHelpTooltipState extends State<HandHelpTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return widget.child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          top: -60 + widget.offset.dy,
          left: 20 + widget.offset.dx,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _animation.value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F5C5C),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.message,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.back_hand,
                      color: Color(0xFF2D7D7D),
                      size: 32,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
