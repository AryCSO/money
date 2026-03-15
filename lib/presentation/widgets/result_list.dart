import 'package:flutter/material.dart';

import '../../data/models/send_result.dart';

class ResultList extends StatelessWidget {
  const ResultList({super.key, required this.results});

  final List<SendResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Text('Nenhum envio realizado ainda.');
    }

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final result = results[index];
        final statusColor = result.success
            ? const Color(0xFF3ECF8E)
            : const Color(0xFFFF7B7B);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161A22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error_rounded,
                color: statusColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.phone,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.message,
                      style: const TextStyle(color: Color(0xFFD8DFEB)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
