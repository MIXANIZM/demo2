import 'package:flutter/material.dart';

class StructurePage extends StatelessWidget {
  const StructurePage({super.key});

  @override
  Widget build(BuildContext context) {
    // В HomeShell уже есть общий Scaffold + AppBar
    return const Center(
      child: Text(
        'Структура',
        style: TextStyle(fontSize: 24),
      ),
    );
  }
}
