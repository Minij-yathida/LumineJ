import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class SizeChip extends StatelessWidget {
  final int size;
  final bool selected;
  final VoidCallback onTap;
  const SizeChip({super.key, required this.size, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(size.toString()),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.brown,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.text,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: AppColors.brown),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
