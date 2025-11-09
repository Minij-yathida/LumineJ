import 'package:flutter/material.dart';

class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool filled; // true = ปุ่มทึบ, false = ปุ่มใส/ขอบไล่สี
  final EdgeInsets padding;

  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.filled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 26, vertical: 16), Color? color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradient = const LinearGradient(
      colors: [Color.fromARGB(255, 248, 138, 4), Color.fromARGB(255, 248, 138, 4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    if (filled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(255, 221, 168, 42).withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(40),
            ),
            padding: padding,
          ),
          child: Text(label, style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      );
    }

    // outline + glassy
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFFFFF).withOpacity(0.35),
            const Color(0xFFFFFFFF).withOpacity(0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          width: 1.2,
          color: const Color.fromARGB(255, 234, 202, 44).withOpacity(0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8F73DA).withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color.fromARGB(255, 232, 198, 47),
          padding: padding,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600)),
      ),
    );
  }
}
