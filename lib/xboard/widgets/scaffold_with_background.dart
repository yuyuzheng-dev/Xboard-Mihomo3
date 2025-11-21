import 'package:flutter/material.dart';

class ScaffoldWithBackground extends StatelessWidget {
  final Widget body;

  const ScaffoldWithBackground({
    super.key,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: body,
      ),
    );
  }
}

extension ColorSchemeValues on Color {
  Color withValues({
    int? alpha,
    int? red,
    int? green,
    int? blue,
  }) {
    return Color.fromARGB(
      alpha ?? this.alpha,
      red ?? this.red,
      green ?? this.green,
      blue ?? this.blue,
    );
  }
}
