import 'package:flutter/material.dart';

import '../core/colors.dart';
import '../services/price_store.dart';

/// One quiet line under prices: "● Live · Prices may be delayed" while the
/// server is pushing, "Prices may be delayed" otherwise.
///
/// Prices come from Yahoo Finance, an unofficial source with no real-time
/// guarantee, so the delay notice always shows; the green dot only says the app
/// is receiving the server's latest numbers.
class PriceFreshnessNote extends StatelessWidget {
  const PriceFreshnessNote({super.key, this.align = MainAxisAlignment.start});

  final MainAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PriceStore.instance,
      builder: (context, _) {
        final live = PriceStore.instance.isLive;
        final style = TextStyle(fontSize: 11, color: AppColors.ink4, height: 1.2);
        return Row(
          mainAxisAlignment: align,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: AppColors.bull, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text('Live · ', style: style.copyWith(color: AppColors.bull)),
            ],
            Text('Prices may be delayed', style: style),
          ],
        );
      },
    );
  }
}
