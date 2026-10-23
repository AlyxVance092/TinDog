import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/dog.dart';
import '../theme.dart';

class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = .97,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: widget.onTap == null
        ? null
        : (_) => setState(() => _pressed = true),
    onTapCancel: widget.onTap == null
        ? null
        : () => setState(() => _pressed = false),
    onTapUp: widget.onTap == null
        ? null
        : (_) => setState(() => _pressed = false),
    onTap: widget.onTap == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            widget.onTap!();
          },
    child: AnimatedScale(
      scale: _pressed && !motionReduced ? widget.scale : 1,
      duration: Duration(milliseconds: motionReduced ? 0 : 110),
      curve: Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.small = false, this.light = false});
  final bool small;
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: small ? 34 : 42,
        height: small ? 34 : 42,
        decoration: BoxDecoration(
          color: TinColors.coral,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.pets_rounded,
          color: Colors.white,
          size: small ? 20 : 25,
        ),
      ),
      const SizedBox(width: 9),
      Text(
        'TinDog',
        style: TextStyle(
          fontFamily: 'Bricolage Grotesque',
          fontSize: small ? 22 : 27,
          fontWeight: FontWeight.w900,
          color: light
              ? Colors.white
              : Theme.of(context).textTheme.bodyLarge?.color,
          letterSpacing: -.7,
        ),
      ),
    ],
  );
}

class DogPortrait extends StatelessWidget {
  const DogPortrait({
    super.key,
    required this.dog,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });
  final Dog dog;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final path = dog.photo;
    if (!path.startsWith('assets/')) {
      final image = File(path);
      if (image.existsSync()) {
        return Image.file(
          image,
          fit: fit,
          alignment: alignment,
          errorBuilder: (_, _, _) => _fallback(),
        );
      }
    }
    if (!path.toLowerCase().endsWith('.svg')) {
      return Image.asset(
        path,
        fit: fit,
        alignment: alignment,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return SvgPicture.asset(
      path,
      fit: fit,
      alignment: alignment,
      placeholderBuilder: (_) => _fallback(),
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() => ColoredBox(
    color: dog.dominantColor.withValues(alpha: .35),
    child: const Center(
      child: Icon(Icons.pets_rounded, color: TinColors.coral, size: 54),
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final decoration = BoxDecoration(
      color:
          color ??
          (dark
              ? Colors.white.withValues(alpha: .055)
              : Colors.white.withValues(alpha: .78)),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: .08)
            : Colors.white.withValues(alpha: .8),
      ),
      boxShadow: [
        BoxShadow(
          color: dark
              ? Colors.black26
              : const Color(0xFF96755E).withValues(alpha: .09),
          blurRadius: 22,
          offset: const Offset(0, 9),
        ),
      ],
    );
    final body = Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );
    return motionReduced
        ? body
        : ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: body,
            ),
          );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Bricolage Grotesque',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.height = 54,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;
  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onPressed,
    child: SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: onPressed == null
              ? TinColors.coral.withValues(alpha: .5)
              : TinColors.coral,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33F2553A),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 23,
                  height: 23,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 19),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class StaggeredIn extends StatefulWidget {
  const StaggeredIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<StaggeredIn> createState() => _StaggeredInState();
}

class _StaggeredInState extends State<StaggeredIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: motionReduced ? 0 : 420),
  )..forward();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delay = ((widget.index * 55).clamp(0, 450) / 1000).toDouble();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress =
            (((_controller.value - delay).clamp(0, 1) / (1 - delay)).clamp(
              0,
              1,
            )).toDouble();
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key, this.height = 380, this.radius = 28});
  final double height;
  final double radius;
  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final light = Theme.of(context).brightness == Brightness.dark ? .09 : .2;
      final color = Theme.of(context).brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFFD9C9BC);
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: motionReduced
                ? light
                : light * (.7 + _controller.value * .4),
          ),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
    },
  );
}

class VerifiedPill extends StatefulWidget {
  const VerifiedPill({super.key});
  @override
  State<VerifiedPill> createState() => _VerifiedPillState();
}

class _VerifiedPillState extends State<VerifiedPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: TinColors.green.withValues(
          alpha: .16 + (motionReduced ? 0 : .08 * _controller.value),
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: TinColors.green.withValues(alpha: .23)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, color: TinColors.green, size: 15),
          SizedBox(width: 5),
          Text(
            'Verificado',
            style: TextStyle(
              color: TinColors.green,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}
