import 'package:flutter/material.dart';

class LoadingIndicator extends StatelessWidget {
  final String message;
  const LoadingIndicator({super.key, this.message = 'กำลังประมวลผล...'});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(message),
      ],
    );
  }
}
