import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CrownLogo extends StatelessWidget {
  final double size;
  final bool withRing;

  const CrownLogo({super.key, this.size = 64, this.withRing = true});

  @override
  Widget build(BuildContext context) {
    if (withRing) {
      return Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F6EE),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFC9A227),
            width: size * 0.02,
          ),
        ),
        child: SvgPicture.asset(
          'assets/surya_yantra_icon-1.svg',
          fit: BoxFit.contain,
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        'assets/surya_yantra_icon-1.svg',
        fit: BoxFit.contain,
      ),
    );
  }
}

