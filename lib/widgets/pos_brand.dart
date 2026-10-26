import 'package:flutter/material.dart';

/// Shared Crunch Cartel identity for the full and compact POS navigation.
class PosBrand extends StatelessWidget {
  const PosBrand({super.key, this.compact = false, this.height = 44});

  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Crunch Cartel POS', image: true,
    child: ExcludeSemantics(child: Row(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/brand/crunch-cartel-icon.png',
        key: const ValueKey('pos_brand_icon'), width: height, height: height,
        fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      if (!compact) ...[
        const SizedBox(width: 6),
        Image.asset('assets/brand/crunch-cartel-wordmark.png',
          key: const ValueKey('pos_brand_wordmark'), width: height * 2.4, height: height,
          fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      ],
    ])),
  );
}
