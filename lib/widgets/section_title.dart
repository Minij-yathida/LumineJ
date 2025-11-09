import 'package:flutter/material.dart';
import 'package:LumineJewelry/core/app_colors.dart';

/// Reusable section title used across the app.
/// - `compact=true` produces a plain [Text] (used in tight flows like checkout).
/// - otherwise renders a padded row with optional action button (used on home page).
class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;
  final bool compact;

  const SectionTitle({
    Key? key,
    required this.title,
    this.actionText,
    this.onAction,
    this.compact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: .3,
                ),
          ),
          const Spacer(),
          if (actionText != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionText!,
                style: TextStyle(
                  color: AppColors.brown,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
