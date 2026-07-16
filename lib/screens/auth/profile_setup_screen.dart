import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../config/colors.dart';
import '../../config/constants.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/routes.dart';
import '../../utils/error_messages.dart';
import '../../widgets/jobsy_pressable.dart';
import '../../widgets/modern_widgets.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _userType;
  int _setupStep = 0;
  File? _profileImage;
  bool _isLoading = false;
  
  // Common fields
  final _locationController = TextEditingController();
  final _phoneController = TextEditingController();
  
  // Employer fields
  final _companyNameController = TextEditingController();
  String? _businessType;
  
  // Worker fields
  final _bioController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  String? _experienceLevel;
  List<String> _selectedSkills = [];
  final _otherSkillController = TextEditingController();
  bool _showOtherSkillField = false;
  
  // Employer other field
  final _otherBusinessTypeController = TextEditingController();
  bool _showOtherBusinessField = false;
  
  final List<String> _businessTypes = [
    'Construction',
    'Retail',
    'Hospitality',
    'Technology',
    'Healthcare',
    'Education',
    'Other',
  ];
  
  final List<String> _experienceLevels = [
    'beginner',
    'intermediate',
    'expert',
  ];
  
  final List<String> _availableSkills = [
    'Plumbing',
    'Electrical',
    'Carpentry',
    'Painting',
    'Welding',
    'Masonry',
    'Roofing',
    'Landscaping',
    'Cleaning',
    'Security',
    'Driving',
    'Cooking',
    'Waiting',
    'Sales',
    'Customer Service',
    'Other',
  ];
  
  bool _draftLoaded = false;
  bool _showDraftBanner = false;
  
  String get _draftStorageKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'guest';
    return 'profile_setup_draft_$userId';
  }

  @override
  void initState() {
    super.initState();
    _locationController.addListener(_saveDraft);
    _phoneController.addListener(_saveDraft);
    _companyNameController.addListener(_saveDraft);
    _bioController.addListener(_saveDraft);
    _hourlyRateController.addListener(_saveDraft);
    _otherSkillController.addListener(_saveDraft);
    _otherBusinessTypeController.addListener(_saveDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDraft());
  }

  Future<void> _saveDraft() async {
    if (!_draftLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'user_type': _userType,
        'setup_step': _setupStep,
        'location': _locationController.text,
        'phone': _phoneController.text,
        'company_name': _companyNameController.text,
        'business_type': _businessType,
        'other_business_type': _otherBusinessTypeController.text,
        'bio': _bioController.text,
        'hourly_rate': _hourlyRateController.text,
        'experience_level': _experienceLevel,
        'selected_skills': _selectedSkills,
        'other_skill': _otherSkillController.text,
        'show_other_skill': _showOtherSkillField,
        'show_other_business': _showOtherBusinessField,
      };
      await prefs.setString(_draftStorageKey, jsonEncode(draft));
    } catch (e) {
      debugPrint('Failed to save profile draft: $e');
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftStorageKey);
      if (raw == null || !mounted) {
        setState(() => _draftLoaded = true);
        return;
      }

      final draft = jsonDecode(raw) as Map<String, dynamic>;
      final hasContent = [
        draft['location'],
        draft['phone'],
        draft['company_name'],
        draft['bio'],
        draft['hourly_rate'],
        draft['other_skill'],
      ].any((v) => v != null && v.toString().trim().isNotEmpty) ||
          (draft['selected_skills'] as List?)?.isNotEmpty == true;

      if (!hasContent) {
        setState(() => _draftLoaded = true);
        return;
      }

      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: JobsyColors.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Continue your profile?',
              style: TextStyle(color: JobsyColors.textPrimary, fontWeight: FontWeight.w700)),
          content: const Text(
            'You started filling in your profile earlier. Would you like to pick up where you left off?',
            style: TextStyle(color: JobsyColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Start over'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (resume == true && mounted) {
        final draftRole = draft['user_type'] as String?;
        final draftStep = draft['setup_step'] as int? ?? 0;
        setState(() {
          if (draftRole != null) _userType = draftRole;
          if (draftStep == 1 && draftRole != null) _setupStep = 1;
          _locationController.text = draft['location']?.toString() ?? '';
          _phoneController.text = draft['phone']?.toString() ?? '';
          _companyNameController.text = draft['company_name']?.toString() ?? '';
          _businessType = draft['business_type'] as String?;
          _otherBusinessTypeController.text =
              draft['other_business_type']?.toString() ?? '';
          _bioController.text = draft['bio']?.toString() ?? '';
          _hourlyRateController.text = draft['hourly_rate']?.toString() ?? '';
          _experienceLevel = draft['experience_level'] as String?;
          _selectedSkills = List<String>.from(draft['selected_skills'] ?? []);
          _otherSkillController.text = draft['other_skill']?.toString() ?? '';
          _showOtherSkillField = draft['show_other_skill'] == true;
          _showOtherBusinessField = draft['show_other_business'] == true;
          _showDraftBanner = true;
        });
      } else {
        await prefs.remove(_draftStorageKey);
      }
    } catch (e) {
      debugPrint('Failed to load profile draft: $e');
    } finally {
      if (mounted) setState(() => _draftLoaded = true);
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftStorageKey);
    } catch (_) {}
  }

  Future<void> _confirmRoleChoice() async {
    if (_userType == null) return;

    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('No user found');

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('user_type')
          .eq('id', userId)
          .maybeSingle();

      final dbRole = profile?['user_type'] as String?;
      if (dbRole != _userType) {
        await Supabase.instance.client.rpc(
          'set_onboarding_user_role',
          params: {'p_target_role': _userType},
        );
      }

      if (mounted) {
        setState(() => _setupStep = 1);
        await _saveDraft();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildRoleChoiceStep() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'How do you want to start?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: JobsyColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'You can switch between hiring and finding work anytime in the app.',
          style: TextStyle(fontSize: 15, color: JobsyColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 28),
        _RoleChoiceCard(
          title: 'Find Work',
          subtitle: 'Browse jobs and apply as a worker',
          icon: Icons.handyman_rounded,
          gradient: JobsyColors.workerGradient,
          selected: _userType == AppConstants.userTypeWorker,
          onTap: () => setState(() => _userType = AppConstants.userTypeWorker),
        ),
        const SizedBox(height: 14),
        _RoleChoiceCard(
          title: 'Hire Workers',
          subtitle: 'Post jobs and review applications',
          icon: Icons.business_center_rounded,
          gradient: JobsyColors.employerGradient,
          selected: _userType == AppConstants.userTypeEmployer,
          onTap: () => setState(() => _userType = AppConstants.userTypeEmployer),
        ),
        const SizedBox(height: 32),
        JobsyGradientButton(
          text: 'Continue',
          height: 56,
          fontSize: 17,
          gradient: _userType == AppConstants.userTypeEmployer
              ? JobsyColors.employerGradient
              : _userType == AppConstants.userTypeWorker
                  ? JobsyColors.workerGradient
                  : JobsyColors.brandGradient,
          isLoading: _isLoading,
          onPressed: _userType == null || _isLoading ? null : _confirmRoleChoice,
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _locationController.dispose();
    _phoneController.dispose();
    _companyNameController.dispose();
    _bioController.dispose();
    _hourlyRateController.dispose();
    _otherSkillController.dispose();
    _otherBusinessTypeController.dispose();
    super.dispose();
  }
  
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    
    if (image != null) {
      setState(() => _profileImage = File(image.path));
    }
  }
  
  Future<String?> _uploadProfilePhoto() async {
    if (_profileImage == null) return null;
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;
      
      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${user.id}/$fileName';
      
      await Supabase.instance.client.storage
          .from('profile-photos')
          .upload(filePath, _profileImage!);
      
      final publicUrl = Supabase.instance.client.storage
          .from('profile-photos')
          .getPublicUrl(filePath);
      
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      return null;
    }
  }
  
  Future<void> _handleSubmit() async {
    if (_userType == null) return;
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No user found');
      
      // Upload photo if selected
      String? photoUrl;
      if (_profileImage != null) {
        photoUrl = await _uploadProfilePhoto();
      }
      
      // Prepare common update data
      Map<String, dynamic> updateData = {
        'location': _locationController.text.trim(),
        'phone': _phoneController.text.trim(),
        'is_profile_complete': true,
      };
      
      if (photoUrl != null) {
        updateData['avatar_url'] = photoUrl;
      }
      
      // Add employer-specific or worker-specific data
      if (_userType == AppConstants.userTypeEmployer) {
        updateData['company_name'] = _companyNameController.text.trim();
        // Handle custom business type from Other field
        if (_businessType == 'Other' && _otherBusinessTypeController.text.trim().isNotEmpty) {
          updateData['business_type'] = _otherBusinessTypeController.text.trim();
        } else if (_businessType != 'Other') {
          updateData['business_type'] = _businessType;
        }
      } else {
        updateData['bio'] = _bioController.text.trim();
        updateData['hourly_rate'] = double.tryParse(_hourlyRateController.text) ?? 0;
        updateData['experience_level'] = _experienceLevel;
        
        // Process skills - handle custom "Other" skills
        List<String> finalSkills = [..._selectedSkills];
        if (_showOtherSkillField && _otherSkillController.text.trim().isNotEmpty) {
          // Remove 'Other' placeholder if exists
          finalSkills.removeWhere((s) => s == 'Other' || !_availableSkills.contains(s));
          // Add custom skills (split by comma and trim)
          final customSkills = _otherSkillController.text
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          finalSkills.addAll(customSkills);
        }
        updateData['skills'] = finalSkills;
      }
      
      // Update profiles table
      await Supabase.instance.client
          .from('profiles')
          .update(updateData)
          .eq('id', user.id);

      await _clearDraft();
      
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.onboardingTutorial,
          arguments: {'userType': _userType ?? AppConstants.userTypeWorker},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_setupStep == 0) {
      return Scaffold(
        backgroundColor: JobsyColors.background,
        appBar: AppBar(
          backgroundColor: JobsyColors.background,
          elevation: 0,
          title: const Text('Set Up Profile'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(child: _buildRoleChoiceStep()),
      );
    }

    final isEmployer = _userType == AppConstants.userTypeEmployer;
    final primaryColor = isEmployer ? JobsyColors.employerPrimary : JobsyColors.workerPrimary;
    
    return Scaffold(
      backgroundColor: JobsyColors.background,
      appBar: AppBar(
        backgroundColor: JobsyColors.background,
        elevation: 0,
        title: const Text('Complete Your Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _isLoading
              ? null
              : () => setState(() {
                    _setupStep = 0;
                    _saveDraft();
                  }),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              if (_showDraftBanner)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restore_rounded, color: primaryColor, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Your saved progress has been restored. Finish and tap Complete Profile.',
                          style: TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              // Profile photo
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor.withOpacity(0.1),
                      image: _profileImage != null
                          ? DecorationImage(
                              image: FileImage(_profileImage!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _profileImage == null
                        ? Icon(Icons.add_a_photo, size: 40, color: primaryColor)
                        : null,
                  ),
                ),
              ),
              
              const SizedBox(height: 8),
              
              const Text(
                'Tap to add photo',
                textAlign: TextAlign.center,
                style: TextStyle(color: JobsyColors.textTertiary, fontSize: 14),
              ),
              
              const SizedBox(height: 32),
              
              // Common fields
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Phone number is required';
                  final digits = value.replaceAll(RegExp(r'[\s\-()]'), '');
                  if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(digits)) {
                    return 'Enter a valid phone number (e.g. +267 72 123 456)';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+267 72 123 456',
                  prefixIcon: Icon(Icons.phone, color: primaryColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _locationController,
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                decoration: InputDecoration(
                  labelText: 'Location',
                  hintText: 'Gaborone, Botswana',
                  prefixIcon: Icon(Icons.location_on, color: primaryColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primaryColor, width: 2),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Employer-specific fields
              if (isEmployer) ...[
                TextFormField(
                  controller: _companyNameController,
                  decoration: InputDecoration(
                    labelText: 'Company Name (Optional)',
                    prefixIcon: Icon(Icons.business, color: primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                DropdownButtonFormField<String>(
                  value: _businessType,
                  hint: const Text(
                    'e.g. Construction, Retail, Hospitality',
                    style: TextStyle(color: JobsyColors.textSecondary),
                  ),
                  decoration: InputDecoration(
                    labelText: 'Business Type',
                    prefixIcon: Icon(Icons.category, color: primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                  items: _businessTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type, style: const TextStyle(color: JobsyColors.textPrimary)),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() {
                    _businessType = value;
                    _showOtherBusinessField = value == 'Other';
                    if (value != 'Other') {
                      _otherBusinessTypeController.clear();
                    }
                  }),
                  validator: (value) => value == null ? 'Required' : null,
                ),
                if (_showOtherBusinessField) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _otherBusinessTypeController,
                    decoration: InputDecoration(
                      labelText: 'Specify Business Type',
                      hintText: 'e.g., Real Estate, Consulting, etc.',
                      prefixIcon: Icon(Icons.add_circle_outline, color: primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                    validator: (value) => _businessType == 'Other' && (value == null || value.trim().isEmpty)
                        ? 'Please specify your business type'
                        : null,
                  ),
                ],
              ],
              
              // Worker-specific fields
              if (!isEmployer) ...[
                DropdownButtonFormField<String>(
                  value: _experienceLevel,
                  decoration: InputDecoration(
                    labelText: 'Experience Level',
                    prefixIcon: Icon(Icons.star, color: primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                  items: _experienceLevels.map((level) {
                    return DropdownMenuItem(
                      value: level,
                      child: Text(level[0].toUpperCase() + level.substring(1)),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _experienceLevel = value),
                  validator: (value) => value == null ? 'Required' : null,
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _hourlyRateController,
                  keyboardType: TextInputType.number,
                  validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                  decoration: InputDecoration(
                    labelText: 'Hourly Rate (BWP)',
                    hintText: '50',
                    prefixIcon: Icon(Icons.attach_money, color: primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Skills selection
                const Text(
                  'Select Your Skills',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableSkills.map((skill) {
                    final isSelected = _selectedSkills.contains(skill) ||
                        (skill == 'Other' && _selectedSkills.any((s) => !_availableSkills.contains(s)));
                    return FilterChip(
                      label: Text(skill),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (skill == 'Other') {
                            _showOtherSkillField = selected;
                            if (!selected) {
                              _selectedSkills.removeWhere((s) => !_availableSkills.contains(s) || s == 'Other');
                              _otherSkillController.clear();
                            }
                          } else {
                            if (selected) {
                              _selectedSkills.add(skill);
                            } else {
                              _selectedSkills.remove(skill);
                            }
                          }
                        });
                      },
                      selectedColor: primaryColor.withOpacity(0.2),
                      checkmarkColor: primaryColor,
                    );
                  }).toList(),
                ),
                if (_showOtherSkillField) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _otherSkillController,
                    decoration: InputDecoration(
                      labelText: 'Specify Other Skills',
                      hintText: 'e.g., Photography, Tutoring, etc.',
                      prefixIcon: Icon(Icons.add_circle_outline, color: primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                      helperText: 'Separate multiple skills with commas',
                    ),
                    maxLines: 2,
                    validator: (value) => _showOtherSkillField && (value == null || value.trim().isEmpty)
                        ? 'Please specify your other skills'
                        : null,
                  ),
                ],
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _bioController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Bio',
                    hintText: 'Tell employers about yourself...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 32),
              
              JobsyGradientButton(
                text: 'Complete Profile',
                height: 56,
                fontSize: 17,
                gradient: isEmployer ? JobsyColors.employerGradient : JobsyColors.workerGradient,
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _handleSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onGradient = JobsyColors.onRoleAccent(gradient.first);

    return JobsyPressable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : JobsyColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? gradient.first : JobsyColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withOpacity(0.2)
                      : gradient.first.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: selected ? onGradient : gradient.first,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: selected ? onGradient : JobsyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? onGradient.withOpacity(0.85)
                            : JobsyColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? onGradient : JobsyColors.textTertiary,
              ),
            ],
          ),
        ),
    );
  }
}
