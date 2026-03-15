import 'package:flutter/material.dart';

class TokenChipList extends StatelessWidget {
  const TokenChipList({super.key, required this.tokens});

  final List<String> tokens;

  @override
  Widget build(BuildContext context) {
    if (tokens.isEmpty) {
      return const Text('Nenhuma variavel detectada no modelo atual.');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tokens
          .map(
            (token) => Chip(
              avatar: const Icon(Icons.tag_rounded, size: 16),
              label: Text(token),
              visualDensity: VisualDensity.compact,
            ),
          )
          .toList(),
    );
  }
}
