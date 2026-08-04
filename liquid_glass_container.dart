import 'dart:ui';
import 'package:flutter/material.dart';

/// A glass container styled after Apple's "Liquid Glass" material
/// (iOS 26 / macOS), built entirely from standard Flutter APIs.
///
/// Compared to plain glassmorphism, this adds the four things that make
/// Apple's material actually read as "glass" instead of "blurred rectangle":
///
/// 1. **Saturation boost on the backdrop** — Apple's own UIKit blur
///    increases background saturation ~50% *before* blurring. We do the
///    same via [ColorFilter.matrix] composed with [ImageFilter.blur].
/// 2. **Continuous "squircle" corners** — via [ClipRSuperellipse] /
///    [RSuperellipse], the real superellipse curve Apple uses (not a
///    circular-arc `BorderRadius`). Requires Flutter 3.32+.
/// 3. **A directional specular border** — a gradient stroke that looks
///    bright where a light source would be catching the edge, and fades
///    elsewhere, instead of one flat border color.
/// 4. **A soft top sheen** — a faint white gradient near the top, like
///    light grazing a curved glass surface.
///
/// This is still backdrop-filter glass, not real optical refraction —
/// content behind it doesn't bend. For actual GPU-shader lensing/
/// refraction (content distorting through the glass), see the note at
/// the bottom of this file.
class LiquidGlassContainer extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AlignmentGeometry? alignment;

  /// Base tint of the glass fill. Defaults to white (light glass).
  /// Use a dark color for glass meant to sit on light backgrounds.
  final Color? color;

  /// Backdrop blur radius.
  final double blur;

  /// Saturation multiplier applied to whatever is behind the glass.
  /// 1.0 = unchanged, >1.0 = more vivid (Apple uses roughly 1.4–1.8).
  final double saturation;

  /// Strength of the specular edge highlight, 0–1+.
  final double specularIntensity;

  /// Direction the "light" is coming from, used for both the sheen and
  /// the specular border gradient. Top-left is the natural default.
  final Alignment lightSource;

  /// Whether to draw the soft top sheen overlay.
  final bool enableSheen;

  final List<BoxShadow>? boxShadow;

  /// If provided, the glass becomes tappable and gives a subtle
  /// press-in response (scale + brighter edge), like an iOS control.
  final VoidCallback? onTap;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius,
    this.padding,
    this.margin,
    this.alignment,
    this.color,
    this.blur = 24.0,
    this.saturation = 1.5,
    this.specularIntensity = 1.0,
    this.lightSource = const Alignment(-0.6, -1.0),
    this.enableSheen = true,
    this.boxShadow,
    this.onTap,
  });

  @override
  State<LiquidGlassContainer> createState() => _LiquidGlassContainerState();
}

class _LiquidGlassContainerState extends State<LiquidGlassContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (widget.onTap == null) return;
    _pressController.animateTo(
      pressed ? 1 : 0,
      curve: pressed ? Curves.easeOut : Curves.easeOutBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final glass = AnimatedBuilder(
      animation: _pressController,
      builder: (context, _) {
        final t = _pressController.value; // 0 = resting, 1 = pressed
        return Transform.scale(
          scale: 1 - (t * 0.025),
          child: _buildGlass(t),
        );
      },
    );

    if (widget.onTap == null) return glass;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: glass,
    );
  }

  Widget _buildGlass(double pressT) {
    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(28);
    final effectiveColor = widget.color ?? Colors.white;

    final composedFilter = ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
      inner: ColorFilter.matrix(_saturationMatrix(widget.saturation)),
    );

    final shadows = widget.boxShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28 - pressT * 0.08),
            blurRadius: 24,
            offset: Offset(0, 12 - pressT * 6),
          ),
        ];

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      alignment: widget.alignment,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        boxShadow: shadows,
      ),
      // ClipRSuperellipse gives the real Apple "squircle" curve — smoother,
      // more continuous corners than ClipRRect. Needs Flutter 3.32+; on
      // older Flutter, swap this (and the painter below) for ClipRRect.
      child: ClipRSuperellipse(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter: composedFilter,
          child: Stack(
            children: [
              Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: widget.lightSource,
                    end: Alignment(-widget.lightSource.x, -widget.lightSource.y),
                    colors: [
                      effectiveColor.withValues(
                        alpha: (0.16 + pressT * 0.02).clamp(0.0, 1.0),
                      ),
                      effectiveColor.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    if (widget.enableSheen)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.30),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 0.55],
                              ),
                            ),
                          ),
                        ),
                      ),
                    widget.child,
                  ],
                ),
              ),
              // Directional specular border — this is what sells the
              // "light catching an edge" look instead of a flat outline.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SpecularBorderPainter(
                      borderRadius: effectiveRadius,
                      lightSource: widget.lightSource,
                      intensity: widget.specularIntensity + pressT * 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints a gradient stroke along the exact squircle path, bright near
/// [lightSource] and fading toward the opposite corner.
class _SpecularBorderPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final Alignment lightSource;
  final double intensity;

  const _SpecularBorderPainter({
    required this.borderRadius,
    required this.lightSource,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.6);
    final rse = RSuperellipse.fromLTRBAndCorners(
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
      topLeft: borderRadius.topLeft,
      topRight: borderRadius.topRight,
      bottomRight: borderRadius.bottomRight,
      bottomLeft: borderRadius.bottomLeft,
    );
    final path = Path()..addRSuperellipse(rse);

    final opposite = Alignment(-lightSource.x, -lightSource.y);
    final gradient = LinearGradient(
      begin: lightSource,
      end: opposite,
      colors: [
        Colors.white.withValues(alpha: (0.75 * intensity).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: (0.10 * intensity).clamp(0.0, 1.0)),
        Colors.white.withValues(alpha: (0.30 * intensity).clamp(0.0, 1.0)),
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = gradient.createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _SpecularBorderPainter old) =>
      old.intensity != intensity ||
      old.borderRadius != borderRadius ||
      old.lightSource != lightSource;
}

/// Standard luminance-preserving saturation matrix. Mirrors what
/// UIKit's own backdrop material does before blurring.
List<double> _saturationMatrix(double saturation) {
  const lumR = 0.2126;
  const lumG = 0.7152;
  const lumB = 0.0722;
  final invSat = 1 - saturation;
  final r = invSat * lumR;
  final g = invSat * lumG;
  final b = invSat * lumB;
  return <double>[
    r + saturation, g, b, 0, 0,
    r, g + saturation, b, 0, 0,
    r, g, b + saturation, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

// ─────────────────────────────────────────────────────────────────────────
// Usage:
//
// LiquidGlassContainer(
//   width: 320,
//   padding: const EdgeInsets.all(20),
//   onTap: () {},
//   child: const Text(
//     'Liquid Glass',
//     style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
//   ),
// )
//
// On dark imagery/backgrounds, saturation ~1.4–1.8 and lightSource near
// topLeft looks closest to Apple's control-center panels. For glass sitting
// on a white background, drop saturation to ~1.0–1.1 and pass a dark color.
// ─────────────────────────────────────────────────────────────────────────
