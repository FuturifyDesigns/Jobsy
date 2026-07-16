import 'package:flutter/material.dart';
import '../../config/colors.dart';

class PhoneVerificationScreen extends StatelessWidget {
  const PhoneVerificationScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      appBar: AppBar(
        backgroundColor: JobsyColors.background,
        iconTheme: const IconThemeData(color: JobsyColors.textPrimary),
      ),
      body: const Center(
        child: Text(
          'Phone Verification',
          style: TextStyle(color: JobsyColors.textPrimary, fontSize: 20),
        ),
      ),
    );
  }
}
