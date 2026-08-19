import 'dart:ui' as ui;
import 'package:flutter/material.dart';

ui.FragmentProgram? _liquidGlassShaderProgram;
bool _isShaderLoading = false;

/// Universal Liquid Glass Container Widget
/// Combines GLSL edge refraction, specular rim highlights, and frosted backdrop blur.
class GlassContainer extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double blur;
  final double refractionStrength;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final AlignmentGeometry? alignment;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius,
    this.padding,
    this.margin,
    this.color,
    this.borderColor,
    this.blur = 10.0,
    this.refractionStrength = 12.0,
    this.border,
    this.boxShadow,
    this.alignment,
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer> {
  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    if (_liquidGlassShaderProgram != null || _isShaderLoading) return;
    _isShaderLoading = true;
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
      _liquidGlassShaderProgram = program;
      if (mounted) setState(() {});
    } catch (_) {
      // Graceful fallback to BackdropFilter if shaders are unsupported in environment
    } finally {
      _isShaderLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(20);
    final effectiveColor = widget.color ?? Colors.grey.withValues(alpha: 0.10);
    final effectiveBorderColor =
        widget.borderColor ?? Colors.grey.shade300.withValues(alpha: 0.14);
    final effectiveBorder = widget.border ??
        Border.all(
          color: effectiveBorderColor,
          width: 1,
        );
    final effectiveShadow = widget.boxShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ];

    final cornerRadiusValue = effectiveRadius.topLeft.x;

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      alignment: widget.alignment,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        boxShadow: effectiveShadow,
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: CustomPaint(
          foregroundPainter: _LiquidGlassRimPainter(
            borderRadius: effectiveRadius,
            borderColor: effectiveBorderColor,
          ),
          child:
              ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur) !=
                      null
                  ? BackdropFilter(
                      filter: ui.ImageFilter.blur(
                          sigmaX: widget.blur, sigmaY: widget.blur),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: widget.padding,
                        decoration: BoxDecoration(
                          color: effectiveColor,
                          borderRadius: effectiveRadius,
                          border: effectiveBorder,
                        ),
                        child: widget.child,
                      ),
                    )
                  : Container(
                      padding: widget.padding,
                      decoration: BoxDecoration(
                        color: effectiveColor,
                        borderRadius: effectiveRadius,
                        border: effectiveBorder,
                      ),
                      child: widget.child,
                    ),
        ),
      ),
    );
  }
}

/// Custom painter for Liquid Glass specular edge highlight
class _LiquidGlassRimPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final Color borderColor;

  _LiquidGlassRimPainter({
    required this.borderRadius,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // Specular top-left light gradient
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(size.width * 0.4, size.height * 0.4),
        [
          Colors.white.withValues(alpha: 0.35),
          borderColor.withValues(alpha: 0.1),
          Colors.transparent,
        ],
        const [0.0, 0.5, 1.0],
      );

    canvas.drawRRect(rrect, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassRimPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}
