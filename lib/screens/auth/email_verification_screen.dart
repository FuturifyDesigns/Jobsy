import 'package:flutter/material.dart';
import '../../config/colors.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});
  
  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  String? _email;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _email = args?['email'];
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      appBar: AppBar(
        backgroundColor: JobsyColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Email icon animation
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: JobsyColors.employerPrimary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.email_outlined,
                  size: 60,
                  color: JobsyColors.employerPrimary,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Check Your Email',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: JobsyColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Description with email
              Text(
                'We\'ve sent a verification link to ${_email ?? 'your email'}. Click the link to verify your account.',
                style: const TextStyle(
                  fontSize: 16,
                  color: JobsyColors.textTertiary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // Resend button
              OutlinedButton(
                onPressed: () {
                  // TODO: Implement resend email
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Verification email sent!')),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: const BorderSide(color: JobsyColors.employerPrimary),
                ),
                child: const Text(
                  'Resend Email',
                  style: TextStyle(
                    fontSize: 16,
                    color: JobsyColors.employerPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: JobsyColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: JobsyColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Tips:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: JobsyColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Check your spam/junk folder\n'
                      '• Make sure the email is correct\n'
                      '• Link expires in 24 hours',
                      style: TextStyle(
                        fontSize: 14,
                        color: JobsyColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
