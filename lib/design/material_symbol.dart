import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MaterialSymbol extends StatelessWidget {
  const MaterialSymbol(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  final String name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/google/symbols/${name}_24px.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ??
            IconTheme.of(context).color ??
            Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
      semanticsLabel: semanticLabel,
    );
  }
}
