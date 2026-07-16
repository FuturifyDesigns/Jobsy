import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io';
import '../../config/colors.dart';
import '../../config/constants.dart';
import '../../config/page_transitions.dart';
import '../../utils/error_messages.dart';
import '../../services/role_service.dart';
import '../../widgets/role_setup_prompt.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _budgetController = TextEditingController();
  final _durationController = TextEditingController();
  final _customSkillController = TextEditingController();

  String? _selectedCategory;
  String _budgetType = 'fixed';
  String? _experienceLevel;
  final List<String> _selectedSkills = [];
  final List<String> _customSkills = [];
  final List<File> _jobPhotos = [];
  DateTime? _startDate;
  bool _isLoading = false;
  bool _isLocatingGPS = false;
  bool _showCustomSkillInput = false;
  double? _locationLat;
  double? _locationLng;

  static const int _maxTotalSkills = 5;
  static const int _maxPhotos = 5;

  final List<String> _categories = AppConstants.jobCategories;

  final List<String> _budgetTypes = ['fixed', 'hourly', 'daily', 'weekly'];
  final List<String> _experienceLevels = ['beginner', 'intermediate', 'expert'];

  final List<String> _availableSkills = [
    'Plumbing',
    'Electrical',
    'Carpentry',
    'Painting',
    'Cleaning',
    'Gardening',
    'Construction',
    'Welding',
    'Masonry',
    'Roofing',
    'Tiling',
    'General Labor',
  ];

  // ── Budget type explanations ────────────────────────
  final Map<String, String> _budgetHints = {
    'fixed': 'A one-time total payment for the entire job, regardless of how long it takes.',
    'hourly': 'Pay per hour worked. Best for jobs where time varies.',
    'daily': 'A flat rate per day of work. Good for multi-day projects.',
    'weekly': 'Pay per full week of work. Ideal for long-term engagements.',
  };

  final Map<String, IconData> _budgetIcons = {
    'fixed': Icons.payments_outlined,
    'hourly': Icons.schedule,
    'daily': Icons.today,
    'weekly': Icons.date_range,
  };

  // ── Profanity filter ────────────────────────────────
  static final List<String> _profanityList = [
    'fuck', 'shit', 'ass', 'bitch', 'damn', 'bastard', 'dick', 'crap',
    'cunt', 'piss', 'slut', 'whore', 'nigger', 'nigga', 'faggot', 'retard',
    'motherfucker', 'bullshit', 'asshole', 'dumbass', 'jackass',
    'idiot', 'stupid', 'moron',
    // Setswana profanity
    'msunu', 'nnyaa', 'sefebe', 'masepa', 'ntlha',
  ];

  bool _containsProfanity(String text) {
    final lower = text.toLowerCase();
    for (final word in _profanityList) {
      if (RegExp(r'\b' + word + r'\b', caseSensitive: false).hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  String? _profanityValidator(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required';
    if (_containsProfanity(value)) {
      return 'Please use appropriate language';
    }
    return null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _budgetController.dispose();
    _durationController.dispose();
    _customSkillController.dispose();
    super.dispose();
  }

  // ── Location methods ────────────────────────────────

  void _showLocationOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: JobsyColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Set Job Location',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: JobsyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you\'d like to set the location',
              style: TextStyle(fontSize: 14, color: JobsyColors.textSecondary),
            ),
            const SizedBox(height: 24),

            // Option 1: Use current location
            _buildLocationOptionTile(
              icon: Icons.my_location,
              color: Colors.green,
              title: 'Use my current location',
              subtitle: 'Pin your GPS location automatically',
              onTap: () {
                Navigator.pop(context);
                _getCurrentLocation();
              },
            ),
            const SizedBox(height: 12),

            // Option 2: Type it manually
            _buildLocationOptionTile(
              icon: Icons.edit_location_alt,
              color: JobsyColors.employerPrimary,
              title: 'Type location manually',
              subtitle: 'Enter the address yourself',
              onTap: () {
                Navigator.pop(context);
                // Focus on the text field
                FocusScope.of(context).requestFocus(FocusNode());
                Future.delayed(const Duration(milliseconds: 200), () {
                  if (mounted) {
                    _showManualLocationDialog();
                  }
                });
              },
            ),

            if (_locationController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildLocationOptionTile(
                icon: Icons.clear,
                color: Colors.red,
                title: 'Clear location',
                subtitle: _locationController.text,
                onTap: () {
                  setState(() {
                    _locationController.clear();
                    _locationLat = null;
                    _locationLng = null;
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationOptionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: JobsyColors.surfaceLight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: JobsyColors.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: JobsyColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocatingGPS = true);

    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permission permanently denied. Enable it in Settings.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Reverse geocode to get address
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        final parts = <String>[
          if (place.street != null && place.street!.isNotEmpty) place.street!,
          if (place.subLocality != null && place.subLocality!.isNotEmpty)
            place.subLocality!,
          if (place.locality != null && place.locality!.isNotEmpty)
            place.locality!,
        ];
        final address = parts.isNotEmpty ? parts.join(', ') : 'Gaborone';

        setState(() {
          _locationController.text = address;
          _locationLat = position.latitude;
          _locationLng = position.longitude;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: JobsyColors.surfaceLight, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Location set: $address')),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('GPS error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get location. Please enter it manually.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocatingGPS = false);
    }
  }

  void _showManualLocationDialog() {
    final controller = TextEditingController(text: _locationController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.edit_location_alt, color: JobsyColors.employerPrimary),
            const SizedBox(width: 10),
            const Text('Enter Location'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'e.g., Gaborone, Block 8',
            prefixIcon:
                Icon(Icons.location_on, color: JobsyColors.employerPrimary),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: JobsyColors.employerPrimary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  _locationController.text = text;
                  _locationLat = null;
                  _locationLng = null;
                });
              }
              Navigator.pop(ctx);
            },
            style: JobsyColors.employerFilledButtonStyle(radius: 10),
            child: const Text('Set Location'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  // ── Image picker with crop ──────────────────────────

  Future<void> _pickAndCropImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: JobsyColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('Add Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildImageSourceOption(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildImageSourceOption(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == ImageSource.gallery) {
      // Multi-pick from gallery
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      for (var file in pickedFiles) {
        if (_jobPhotos.length >= _maxPhotos) break;
        final cropped = await _cropImage(File(file.path));
        if (cropped != null && mounted) {
          setState(() => _jobPhotos.add(cropped));
        }
      }
    } else {
      // Single pick from camera
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );
      if (picked != null) {
        final cropped = await _cropImage(File(picked.path));
        if (cropped != null && mounted) {
          setState(() {
            if (_jobPhotos.length < _maxPhotos) _jobPhotos.add(cropped);
          });
        }
      }
    }
  }

  Future<File?> _cropImage(File imageFile) async {
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Edit Photo',
            toolbarColor: JobsyColors.employerPrimary,
            toolbarWidgetColor: JobsyColors.employerOnAccent,
            activeControlsWidgetColor: JobsyColors.employerPrimary,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Edit Photo',
            aspectRatioPickerButtonHidden: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
          ),
        ],
      );
      if (croppedFile != null) {
        return File(croppedFile.path);
      }
    } catch (e) {
      debugPrint('Crop error: $e');
    }
    return null;
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          border: Border.all(color: JobsyColors.surfaceLight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: JobsyColors.employerPrimary),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ── Custom skills ───────────────────────────────────

  int get _totalSkillCount => _selectedSkills.length;
  bool get _canAddMoreSkills => _totalSkillCount < _maxTotalSkills;

  void _addCustomSkill() {
    final skill = _customSkillController.text.trim();
    if (skill.isEmpty) return;

    if (_containsProfanity(skill)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please use appropriate language for skill names'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (skill.length > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Skill name must be 30 characters or less'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check duplicates
    final lower = skill.toLowerCase();
    if (_availableSkills.any((s) => s.toLowerCase() == lower) ||
        _customSkills.any((s) => s.toLowerCase() == lower)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This skill already exists'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_canAddMoreSkills) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Maximum $_maxTotalSkills skills allowed'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _customSkills.add(skill);
      _selectedSkills.add(skill);
      _customSkillController.clear();
    });
  }

  // ── Date picker ─────────────────────────────────────

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: JobsyColors.employerPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  // ── Upload photos ───────────────────────────────────

  Future<List<String>> _uploadJobPhotos() async {
    final List<String> photoUrls = [];
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      for (int i = 0; i < _jobPhotos.length; i++) {
        final file = _jobPhotos[i];
        final fileExt = file.path.split('.').last;
        final fileName =
            '$userId/${DateTime.now().millisecondsSinceEpoch}_$i.$fileExt';
        await Supabase.instance.client.storage
            .from('job-photos')
            .upload(fileName, file);
        final publicUrl = Supabase.instance.client.storage
            .from('job-photos')
            .getPublicUrl(fileName);
        photoUrls.add(publicUrl);
      }
    } catch (e) {
      debugPrint('Error uploading photos: $e');
    }
    return photoUrls;
  }

  // ── Submit handler ──────────────────────────────────

  Future<void> _handlePostJob() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a job location'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Final profanity check on all text fields
    final fieldsToCheck = {
      'Title': _titleController.text,
      'Description': _descriptionController.text,
      'Location': _locationController.text,
    };

    for (final entry in fieldsToCheck.entries) {
      if (_containsProfanity(entry.value)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Inappropriate language detected in ${entry.key} field'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (!await RoleService.isEmployerMode()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Switch to Employer mode in your profile to post jobs.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (!await RoleService.isEmployerProfileReadyForPost()) {
        final ready = await RoleSetupPrompt.showIfNeeded(
          context,
          role: AppConstants.userTypeEmployer,
          requiredForAction: true,
        );
        if (!ready) return;
      }

      final userId = Supabase.instance.client.auth.currentUser!.id;
      final photoUrls = await _uploadJobPhotos();

      await Supabase.instance.client.from('jobs').insert({
        'employer_id': userId,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'location': _locationController.text.trim(),
        if (_locationLat != null && _locationLng != null) ...{
          'latitude': _locationLat,
          'longitude': _locationLng,
        },
        'budget_amount': double.parse(_budgetController.text),
        'budget_type': _budgetType,
        'required_skills': _selectedSkills,
        'experience_level': _experienceLevel,
        'job_photos': photoUrls,
        'start_date': _startDate?.toIso8601String(),
        'duration_days': _durationController.text.isNotEmpty
            ? int.parse(_durationController.text)
            : null,
        'status': 'active',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Job posted successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(friendlyErrorMessage(e))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JobsyColors.background,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            // ── Sliver App Bar with gradient header ────
            SliverAppBar(
              expandedHeight: 180,
              floating: false,
              pinned: true,
              backgroundColor: JobsyColors.background,
              foregroundColor: JobsyColors.textPrimary,
              elevation: 0,
              title: const Text('Post a Job',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF3F3F46),
                            Color(0xFF27272A),
                            Color(0xFF1A1A2E),
                          ],
                          stops: [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      top: -40,
                      right: -40,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.15),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.25),
                                      width: 0.7,
                                    ),
                                  ),
                                  child: const Icon(Icons.add_business_rounded,
                                      color: Colors.white, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ShaderMask(
                                        shaderCallback: (bounds) => const LinearGradient(
                                          colors: [
                                            Color(0xFFFFFFFF),
                                            Color(0xFFCBD5E1),
                                            Color(0xFFFFFFFF),
                                          ],
                                          stops: [0.0, 0.5, 1.0],
                                        ).createShader(bounds),
                                        child: const Text(
                                          'Create a New Job',
                                          style: TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Fill in the details to find the right worker',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.white.withOpacity(0.75),
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Form body ──────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ─ Section: Basic Info ─────────────────
                  _buildSectionHeader(
                      'Basic Information', Icons.info_outline),
                  const SizedBox(height: 16),

                  // Job Title
                  _buildTextField(
                    controller: _titleController,
                    label: 'Job Title *',
                    hint: 'Short, clear headline (min. 3 characters)',
                    helperText:
                        'Example: Urgent plumbing repair — materials supplied',
                    icon: Icons.work_outline,
                    validator: (value) =>
                        _profanityValidator(value, 'Title'),
                  ),
                  const SizedBox(height: 16),

                  // Category
                  _buildDropdown(
                    label: 'Category *',
                    value: _selectedCategory,
                    items: _categories,
                    hint: 'Select a job category',
                    icon: Icons.category_outlined,
                    onChanged: (value) =>
                        setState(() => _selectedCategory = value),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  _buildTextField(
                    controller: _descriptionController,
                    label: 'Job Description *',
                    hint: 'What, where, timing, tools needed…',
                    helperText:
                        'Minimum 20 characters. The more detail, the better applicants you get.',
                    icon: Icons.description_outlined,
                    maxLines: 5,
                    validator: (value) {
                      final base = _profanityValidator(value, 'Description');
                      if (base != null) return base;
                      if (value!.trim().length < 20) {
                        return 'Please provide at least 20 characters';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 28),

                  // ─ Section: Location ───────────────────
                  _buildSectionHeader('Location', Icons.location_on_outlined),
                  const SizedBox(height: 16),
                  _buildLocationPicker(),

                  const SizedBox(height: 28),

                  // ─ Section: Budget ─────────────────────
                  _buildSectionHeader(
                      'Budget & Payment', Icons.account_balance_wallet_outlined),
                  const SizedBox(height: 16),
                  _buildBudgetTypeSelector(),
                  const SizedBox(height: 16),
                  _buildBudgetAmountField(),

                  const SizedBox(height: 28),

                  // ─ Section: Skills ─────────────────────
                  _buildSectionHeader(
                      'Required Skills', Icons.handyman_outlined),
                  const SizedBox(height: 8),
                  Text(
                    'Select relevant skills or add your own (max $_maxTotalSkills)',
                    style: TextStyle(fontSize: 13, color: JobsyColors.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  _buildSkillsSelector(),

                  const SizedBox(height: 28),

                  // ─ Section: Details ────────────────────
                  _buildSectionHeader(
                      'Additional Details', Icons.tune_outlined),
                  const SizedBox(height: 16),

                  // Experience Level
                  _buildDropdown(
                    label: 'Experience Level (Optional)',
                    value: _experienceLevel,
                    items: _experienceLevels,
                    hint: 'Select experience level',
                    icon: Icons.star_outline,
                    onChanged: (value) =>
                        setState(() => _experienceLevel = value),
                  ),
                  const SizedBox(height: 16),

                  // Start Date
                  _buildDatePicker(),
                  const SizedBox(height: 16),

                  // Duration
                  _buildTextField(
                    controller: _durationController,
                    label: 'Duration (days, optional)',
                    hint: 'e.g. 7',
                    helperText:
                        'Optional — rough job length so workers can plan. Leave blank if unsure.',
                    icon: Icons.timelapse_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final n = int.tryParse(value);
                        if (n == null || n <= 0) {
                          return 'Enter a positive number';
                        }
                        if (n > 365) return 'Maximum 365 days';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 28),

                  // ─ Section: Photos ─────────────────────
                  _buildSectionHeader('Job Photos', Icons.photo_library_outlined),
                  const SizedBox(height: 8),
                  Text(
                    'Add photos of the job site or work needed (max $_maxPhotos). You can crop, rotate, and zoom.',
                    style: TextStyle(fontSize: 13, color: JobsyColors.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  _buildPhotoPicker(),

                  const SizedBox(height: 36),

                  // ─ Submit Button ───────────────────────
                  AnimatedPressButton(
                    scaleDown: 0.97,
                    onPressed: _isLoading ? null : _handlePostJob,
                    child: Container(
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: _isLoading
                            ? null
                            : const LinearGradient(
                                colors: JobsyColors.employerGradient,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        color: _isLoading ? JobsyColors.surfaceElevated : null,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _isLoading
                            ? null
                            : [
                                BoxShadow(
                                  color: JobsyColors.employerPrimary.withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                    color: JobsyColors.employerOnAccent, strokeWidth: 2.5),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.publish_rounded,
                                      size: 22, color: JobsyColors.employerOnAccent),
                                  SizedBox(width: 10),
                                  Text('Post Job',
                                      style: JobsyColors.employerGradientLabelStyle.copyWith(
                                        fontSize: 17,
                                        letterSpacing: 0.2,
                                      )),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  SECTION WIDGETS
  // ══════════════════════════════════════════════════════

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: JobsyColors.employerPrimary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: JobsyColors.employerPrimary.withOpacity(0.3),
              width: 0.6,
            ),
          ),
          child: Icon(icon, color: JobsyColors.employerPrimary, size: 17),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: JobsyColors.textPrimary,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }

  // ── Location picker widget ──────────────────────────

  Widget _buildLocationPicker() {
    final hasLocation = _locationController.text.isNotEmpty;
    return GestureDetector(
      onTap: _isLocatingGPS ? null : _showLocationOptions,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasLocation
                ? JobsyColors.employerPrimary.withOpacity(0.5)
                : JobsyColors.border,
            width: hasLocation ? 2 : 1.5,
          ),
          boxShadow: hasLocation
              ? [
                  BoxShadow(
                    color: JobsyColors.employerPrimary.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: _isLocatingGPS
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('Getting your location...',
                      style: TextStyle(color: JobsyColors.textSecondary)),
                ],
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: hasLocation
                          ? JobsyColors.employerPrimary.withOpacity(0.1)
                          : JobsyColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasLocation ? Icons.location_on : Icons.add_location_alt,
                      color: hasLocation
                          ? JobsyColors.employerPrimary
                          : JobsyColors.textTertiary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasLocation ? 'Job Location' : 'Set Job Location *',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasLocation
                                ? JobsyColors.employerPrimary
                                : JobsyColors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasLocation
                              ? _locationController.text
                              : 'Tap to set location via GPS or type manually',
                          style: TextStyle(
                            fontSize: 15,
                            color:
                                hasLocation ? JobsyColors.textPrimary : JobsyColors.textTertiary,
                            fontWeight: hasLocation
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_locationLat != null && _locationLng != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.gps_fixed_rounded,
                                  size: 13,
                                  color: JobsyColors.employerPrimary.withOpacity(0.85)),
                              const SizedBox(width: 4),
                              Text(
                                'Exact GPS pin saved for directions',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: JobsyColors.employerPrimary.withOpacity(0.85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: JobsyColors.textTertiary),
                ],
              ),
      ),
    );
  }

  // ── Budget type selector with hints ─────────────────

  Widget _buildBudgetTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _budgetTypes.map((type) {
            final isSelected = _budgetType == type;
            return AnimatedPressButton(
              scaleDown: 0.94,
              onPressed: () => setState(() => _budgetType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: JobsyColors.employerGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : JobsyColors.surfaceLight,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : JobsyColors.border.withOpacity(0.5),
                    width: 0.7,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: JobsyColors.employerPrimary.withOpacity(0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _budgetIcons[type],
                      size: 16,
                      color: isSelected
                          ? JobsyColors.employerOnAccent
                          : JobsyColors.textSecondary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      type[0].toUpperCase() + type.substring(1),
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? JobsyColors.employerOnAccent
                            : JobsyColors.textSecondary,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Animated hint
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Container(
            key: ValueKey(_budgetType),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: JobsyColors.employerPrimary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: JobsyColors.employerPrimary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 18,
                    color: JobsyColors.employerPrimary.withOpacity(0.7)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _budgetHints[_budgetType]!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: JobsyColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Budget amount field with Pula prefix ────────────

  Widget _buildBudgetAmountField() {
    return TextFormField(
      controller: _budgetController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Budget is required';
        final amount = double.tryParse(value);
        if (amount == null) return 'Enter a valid amount';
        if (amount <= 0) return 'Amount must be greater than 0';
        if (amount > 1000000) return 'Amount seems too high';
        return null;
      },
      style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: JobsyColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Budget Amount (BWP) *',
        hintText: '0.00',
        helperText:
            'Total pay in Pula for this job. Must be greater than 0.',
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: const TextStyle(
            color: JobsyColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 14),
        floatingLabelStyle: const TextStyle(
            color: JobsyColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        hintStyle: TextStyle(
            color: JobsyColors.border,
            fontSize: 20,
            fontWeight: FontWeight.bold),
        prefixIcon: Container(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'P',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: JobsyColors.employerPrimary,
                ),
              ),
            ],
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: JobsyColors.inputBackground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: JobsyColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              BorderSide(color: JobsyColors.employerPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }

  // ── Skills selector with "Other" ────────────────────

  Widget _buildSkillsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Predefined skills
            ..._availableSkills.map((skill) {
              final isSelected = _selectedSkills.contains(skill);
              return FilterChip(
                label: Text(skill),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected && _canAddMoreSkills) {
                      _selectedSkills.add(skill);
                    } else if (!selected) {
                      _selectedSkills.remove(skill);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Maximum $_maxTotalSkills skills allowed'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  });
                },
                selectedColor:
                    JobsyColors.employerPrimary.withOpacity(0.15),
                checkmarkColor: JobsyColors.employerPrimary,
                labelStyle: TextStyle(
                  color: isSelected
                      ? JobsyColors.employerPrimary
                      : JobsyColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                side: BorderSide(
                  color: isSelected
                      ? JobsyColors.employerPrimary.withOpacity(0.5)
                      : JobsyColors.border,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              );
            }),

            // Custom skills chips (removable)
            ..._customSkills.map((skill) {
              return Chip(
                label: Text(skill),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() {
                    _customSkills.remove(skill);
                    _selectedSkills.remove(skill);
                  });
                },
                backgroundColor:
                    Colors.orange.withOpacity(0.1),
                deleteIconColor: Colors.orange,
                labelStyle: const TextStyle(
                    color: Colors.deepOrange, fontWeight: FontWeight.w600),
                side: BorderSide(
                    color: Colors.orange.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              );
            }),

            // "+ Other" button
            if (_canAddMoreSkills)
              ActionChip(
                avatar: Icon(
                  _showCustomSkillInput ? Icons.close : Icons.add,
                  size: 18,
                  color: JobsyColors.textSecondary,
                ),
                label: Text(_showCustomSkillInput ? 'Cancel' : 'Other'),
                onPressed: () {
                  setState(() {
                    _showCustomSkillInput = !_showCustomSkillInput;
                    if (!_showCustomSkillInput) {
                      _customSkillController.clear();
                    }
                  });
                },
                side: BorderSide(
                    color: JobsyColors.textTertiary!, style: BorderStyle.solid),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
          ],
        ),

        // Custom skill input
        if (_showCustomSkillInput) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customSkillController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 30,
                  decoration: InputDecoration(
                    hintText: 'Enter a custom skill',
                    counterText: '',
                    prefixIcon: Icon(Icons.edit,
                        color: JobsyColors.employerPrimary, size: 20),
                    filled: true,
                    fillColor: JobsyColors.inputBackground,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: JobsyColors.border, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: JobsyColors.employerPrimary, width: 2),
                    ),
                  ),
                  onSubmitted: (_) => _addCustomSkill(),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: JobsyColors.employerPrimary,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _addCustomSkill,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child:
                        Icon(Icons.add, color: JobsyColors.surfaceLight, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ],

        // Skill count indicator
        if (_totalSkillCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$_totalSkillCount / $_maxTotalSkills skills selected',
            style: TextStyle(
              fontSize: 12,
              color: _totalSkillCount >= _maxTotalSkills
                  ? Colors.orange
                  : JobsyColors.textTertiary,
              fontWeight: _totalSkillCount >= _maxTotalSkills
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }

  // ── Date picker tile ────────────────────────────────

  Widget _buildDatePicker() {
    final hasDate = _startDate != null;
    return GestureDetector(
      onTap: _selectDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasDate
                ? JobsyColors.employerPrimary.withOpacity(0.5)
                : JobsyColors.border,
            width: hasDate ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                color: hasDate
                    ? JobsyColors.employerPrimary
                    : JobsyColors.textTertiary,
                size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                hasDate
                    ? 'Starts: ${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                    : 'Start Date (Optional)',
                style: TextStyle(
                  fontSize: 15,
                  color: hasDate ? JobsyColors.textPrimary : JobsyColors.textTertiary,
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (hasDate)
              GestureDetector(
                onTap: () => setState(() => _startDate = null),
                child: Icon(Icons.close, size: 18, color: JobsyColors.textTertiary),
              )
            else
              Icon(Icons.arrow_forward_ios, size: 14, color: JobsyColors.textTertiary),
          ],
        ),
      ),
    );
  }

  // ── Photo picker with crop preview ──────────────────

  Widget _buildPhotoPicker() {
    return Column(
      children: [
        if (_jobPhotos.isNotEmpty) ...[
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _jobPhotos.length + (_jobPhotos.length < _maxPhotos ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == _jobPhotos.length) {
                  return _buildAddPhotoButton();
                }
                return _buildPhotoThumbnail(index);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_jobPhotos.length} / $_maxPhotos photos',
            style: TextStyle(fontSize: 12, color: JobsyColors.textTertiary),
          ),
        ] else
          _buildEmptyPhotoArea(),
      ],
    );
  }

  Widget _buildPhotoThumbnail(int index) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () async {
            // Re-crop existing photo
            final reCropped = await _cropImage(_jobPhotos[index]);
            if (reCropped != null && mounted) {
              setState(() => _jobPhotos[index] = reCropped);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              _jobPhotos[index],
              width: 120,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Remove button
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: () => setState(() => _jobPhotos.removeAt(index)),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.close, color: JobsyColors.surfaceLight, size: 16),
            ),
          ),
        ),
        // Edit hint
        Positioned(
          bottom: 6,
          left: 6,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.crop, color: JobsyColors.surfaceLight, size: 12),
                SizedBox(width: 3),
                Text('Edit',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddPhotoButton() {
    return GestureDetector(
      onTap: _pickAndCropImage,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: JobsyColors.border, width: 2, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo, color: JobsyColors.textTertiary, size: 32),
            const SizedBox(height: 4),
            Text('Add Photo',
                style: TextStyle(fontSize: 11, color: JobsyColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPhotoArea() {
    return GestureDetector(
      onTap: _pickAndCropImage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: JobsyColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: JobsyColors.border, width: 2, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: JobsyColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_photo_alternate,
                  color: JobsyColors.textTertiary, size: 36),
            ),
            const SizedBox(height: 12),
            Text('Tap to add photos',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JobsyColors.textSecondary)),
            const SizedBox(height: 4),
            Text('You can crop, rotate & zoom before uploading',
                style: TextStyle(fontSize: 12, color: JobsyColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════
  //  REUSABLE FORM WIDGETS
  // ══════════════════════════════════════════════════════

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? helperText,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final isMultiLine = maxLines > 1;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(fontSize: 16, color: JobsyColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: const TextStyle(
            color: JobsyColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 14),
        floatingLabelStyle: const TextStyle(
            color: JobsyColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        hintStyle: TextStyle(color: JobsyColors.textTertiary, fontSize: 14),
        prefixIcon: Padding(
          padding: EdgeInsets.only(
            top: isMultiLine ? 16 : 0,
            left: 12,
            right: 4,
          ),
          child: Align(
            alignment: isMultiLine ? Alignment.topCenter : Alignment.center,
            widthFactor: 1.0,
            heightFactor: isMultiLine ? null : null,
            child: Icon(icon, color: JobsyColors.employerPrimary),
          ),
        ),
        prefixIconConstraints: isMultiLine
            ? const BoxConstraints(minWidth: 48, minHeight: 48)
            : null,
        filled: true,
        fillColor: JobsyColors.inputBackground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: JobsyColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              BorderSide(color: JobsyColors.employerPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: const TextStyle(
            color: JobsyColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 14),
        floatingLabelStyle: const TextStyle(
            color: JobsyColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        prefixIcon: Icon(icon, color: JobsyColors.employerPrimary),
        filled: true,
        fillColor: JobsyColors.inputBackground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: JobsyColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              BorderSide(color: JobsyColors.employerPrimary, width: 2),
        ),
      ),
      hint: Text(hint, style: TextStyle(color: JobsyColors.textTertiary)),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(item[0].toUpperCase() + item.substring(1)),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
