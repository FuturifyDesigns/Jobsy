import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/colors.dart';
import '../config/constants.dart';
import '../services/role_service.dart';
import 'modern_widgets.dart';

/// Prompts for role-specific fields after switching — save and continue, no blocking.
class RoleSetupPrompt {
  RoleSetupPrompt._();

  /// Shows setup dialog if fields are missing. Returns true when profile is ready.
  static Future<bool> showIfNeeded(
    BuildContext context, {
    required String role,
    bool requiredForAction = false,
  }) async {
    if (!context.mounted) return false;

    final missing = await RoleService.missingSetupFields(role);
    if (missing.isEmpty) return true;

    if (!context.mounted) return false;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: !requiredForAction,
      builder: (ctx) => _RoleSetupDialog(
        role: role,
        missing: missing,
        requiredForAction: requiredForAction,
      ),
    );
    return saved ?? false;
  }
}

class _RoleSetupDialog extends StatefulWidget {
  final String role;
  final List<RoleSetupField> missing;
  final bool requiredForAction;

  const _RoleSetupDialog({
    required this.role,
    required this.missing,
    required this.requiredForAction,
  });

  @override
  State<_RoleSetupDialog> createState() => _RoleSetupDialogState();
}

class _RoleSetupDialogState extends State<_RoleSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hourlyRateController = TextEditingController();
  final _companyController = TextEditingController();
  final _otherBusinessController = TextEditingController();

  String? _experienceLevel;
  String? _businessType;
  bool _saving = false;

  bool get _isWorker => widget.role == AppConstants.userTypeWorker;
  Color get _accent =>
      _isWorker ? JobsyColors.workerPrimary : JobsyColors.employerPrimary;

  static const _experienceLevels = ['beginner', 'intermediate', 'expert'];
  static const _businessTypes = [
    'Construction',
    'Retail',
    'Hospitality',
    'Technology',
    'Healthcare',
    'Education',
    'Agriculture',
    'Manufacturing',
    'Services',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('hourly_rate, experience_level, company_name, business_type')
          .eq('id', userId)
          .maybeSingle();
      if (profile == null || !mounted) return;

      setState(() {
        _experienceLevel = profile['experience_level'] as String?;
        _hourlyRateController.text = profile['hourly_rate']?.toString() ?? '';
        _companyController.text = profile['company_name']?.toString() ?? '';
        _businessType = profile['business_type'] as String?;
        if (_businessType != null &&
            !_businessTypes.contains(_businessType) &&
            _businessType != 'Other') {
          _otherBusinessController.text = _businessType!;
          _businessType = 'Other';
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _hourlyRateController.dispose();
    _companyController.dispose();
    _otherBusinessController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final updates = <String, dynamic>{};

      if (_isWorker) {
        if (widget.missing.contains(RoleSetupField.experienceLevel)) {
          updates['experience_level'] = _experienceLevel;
        }
        if (widget.missing.contains(RoleSetupField.hourlyRate)) {
          updates['hourly_rate'] =
              double.tryParse(_hourlyRateController.text.trim()) ?? 0;
        }
      } else {
        if (widget.missing.contains(RoleSetupField.companyName)) {
          updates['company_name'] = _companyController.text.trim();
        }
        if (widget.missing.contains(RoleSetupField.businessType)) {
          if (_businessType == 'Other') {
            updates['business_type'] = _otherBusinessController.text.trim();
          } else {
            updates['business_type'] = _businessType;
          }
        }
      }

      if (updates.isNotEmpty) {
        await Supabase.instance.client
            .from('profiles')
            .update(updates)
            .eq('id', userId);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = RoleService.roleLabel(widget.role);
    final subtitle = _isWorker
        ? 'Add a few worker details so employers can review your applications.'
        : 'Add your business details so workers know who they\'re working for.';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [JobsyColors.surfaceLight, JobsyColors.surface],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _accent.withOpacity(0.2)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              JobsyDialogHeader(
                icon: _isWorker ? Icons.engineering_rounded : Icons.business_rounded,
                title: 'Set up $roleLabel mode',
                subtitle: subtitle,
                accentColor: _accent,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isWorker) ..._workerFields() else ..._employerFields(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: JobsyColors.roleFilledButtonStyle(_accent),
                        child: _saving
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: JobsyColors.onRoleAccent(_accent),
                                ),
                              )
                            : const Text(
                                'Save and continue',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    if (!widget.requiredForAction) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.pop(context, false),
                        child: Text(
                          'Skip for now',
                          style: TextStyle(color: JobsyColors.textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _workerFields() {
    return [
      if (widget.missing.contains(RoleSetupField.experienceLevel)) ...[
        const Text(
          'Experience level',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: JobsyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _experienceLevels.contains(_experienceLevel)
              ? _experienceLevel
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: JobsyColors.inputBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          dropdownColor: JobsyColors.surfaceLight,
          hint: const Text('Select experience'),
          items: _experienceLevels
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e[0].toUpperCase() + e.substring(1)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _experienceLevel = v),
          validator: (v) =>
              v == null || v.isEmpty ? 'Experience level is required' : null,
        ),
        const SizedBox(height: 16),
      ],
      if (widget.missing.contains(RoleSetupField.hourlyRate))
        JobsyTextField(
          controller: _hourlyRateController,
          label: 'Hourly rate (P)',
          hint: 'e.g. 50',
          prefixIcon: Icons.payments_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          accentColor: _accent,
          validator: (v) {
            final n = double.tryParse(v?.trim() ?? '');
            if (n == null || n <= 0) return 'Enter a valid hourly rate';
            return null;
          },
        ),
    ];
  }

  List<Widget> _employerFields() {
    return [
      if (widget.missing.contains(RoleSetupField.companyName)) ...[
        JobsyTextField(
          controller: _companyController,
          label: 'Company name',
          hint: 'Your company or business',
          prefixIcon: Icons.business_rounded,
          accentColor: _accent,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Company name is required' : null,
        ),
        const SizedBox(height: 16),
      ],
      if (widget.missing.contains(RoleSetupField.businessType)) ...[
        const Text(
          'Business type',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: JobsyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _businessType != null &&
                  (_businessTypes.contains(_businessType) ||
                      _businessType == 'Other')
              ? _businessType
              : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: JobsyColors.inputBackground,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          dropdownColor: JobsyColors.surfaceLight,
          hint: const Text('Select business type'),
          items: _businessTypes
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) => setState(() => _businessType = v),
          validator: (v) =>
              v == null || v.isEmpty ? 'Business type is required' : null,
        ),
        if (_businessType == 'Other') ...[
          const SizedBox(height: 12),
          JobsyTextField(
            controller: _otherBusinessController,
            label: 'Describe your business',
            hint: 'e.g. Event planning',
            prefixIcon: Icons.edit_rounded,
            accentColor: _accent,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Please describe your business type'
                : null,
          ),
        ],
      ],
    ];
  }
}
