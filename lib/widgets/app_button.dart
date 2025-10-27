import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool primary;

  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: primary ? Theme.of(context).colorScheme.primary : null,
        foregroundColor: primary ? Colors.white : null,
      ),
      onPressed: onPressed,
      child: Text(text),
    );
  }
}
