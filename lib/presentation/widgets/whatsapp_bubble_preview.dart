import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class WhatsAppBubblePreview extends StatelessWidget {
  const WhatsAppBubblePreview({
    super.key,
    required this.messages,
  });

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.chatBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.2),
          ),
        ),
        child: const Center(
          child: Text(
            'A previa das mensagens vai aparecer aqui.',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chatBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.2),
        ),
        image: const DecorationImage(
          image: AssetImage('lib/assets/coin.png'),
          opacity: 0.03,
          fit: BoxFit.none,
          alignment: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < messages.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _BubbleItem(
              text: messages[i],
              time: timeStr,
            ),
          ],
        ],
      ),
    );
  }
}

class _BubbleItem extends StatelessWidget {
  const _BubbleItem({
    required this.text,
    required this.time,
  });

  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.chatOutgoingBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SelectableText(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 15,
                      color: AppColors.chatTick.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
