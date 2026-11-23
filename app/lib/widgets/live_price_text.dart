import 'package:flutter/material.dart';

import '../core/colors.dart';

/// A price that flashes green when it ticks up and red when it ticks down, the
/// way a broker's watchlist does, then fades back over [duration].
///
/// Only the price value drives the flash: the first build and any rebuild with
/// the same [value] stay calm, so a screen refresh never looks like a tick.
class LivePriceText extends StatefulWidget {
  const LivePriceText(
    this.text, {
    super.key,
    required this.value,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.duration = const Duration(milliseconds: 900),
  });

  /// The formatted price to show.
  final String text;

  /// The raw price, compared between builds to pick the flash direction.
  final double? value;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final Duration duration;

  @override
  State<LivePriceText> createState() => _LivePriceTextState();
}

class _LivePriceTextState extends State<LivePriceText> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: widget.duration, value: 1);
  bool _up = true;

  @override
  void didUpdateWidget(covariant LivePriceText old) {
    super.didUpdateWidget(old);
    final prev = old.value;
    final next = widget.value;
    if (prev == null || next == null || prev == next || prev <= 0 || next <= 0) return;
    _up = next > prev;
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        // 0 = just ticked (full colour), 1 = settled (normal text).
        final t = Curves.easeOut.transform(_fade.value);
        final tick = _up ? AppColors.bull : AppColors.bear;
        final base = widget.style?.color ?? DefaultTextStyle.of(context).style.color ?? AppColors.ink;
        final color = Color.lerp(tick, base, t);
        final bg = Color.lerp(tick.withValues(alpha: 0.16), tick.withValues(alpha: 0), t);
        return DecoratedBox(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Text(
            widget.text,
            style: (widget.style ?? const TextStyle()).copyWith(color: color),
            textAlign: widget.textAlign,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
          ),
        );
      },
    );
  }
}
