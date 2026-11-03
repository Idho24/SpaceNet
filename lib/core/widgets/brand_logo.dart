import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  final double width;

  const BrandLogo({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/spacenet_logo.png',
      width: width,
      fit: BoxFit.contain,
      semanticLabel: 'SpaceNet',
    );
  }
}
