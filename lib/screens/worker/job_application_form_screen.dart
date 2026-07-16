import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../config/colors.dart';

/// Returned to [JobDetailsScreen] when the worker submits the apply form.
class JobApplicationFormResult {
  final String coverLetter;
  final String referencesText;
  final String additionalInfo;
  final List<PlatformFile> qualificationFiles;

  const JobApplicationFormResult({
    required this.coverLetter,
    required this.referencesText,
    required this.additionalInfo,
    required this.qualificationFiles,
  });
}

/// Full-screen apply form so every field (references, uploads, notes) is visible
/// without dialog height / scroll clipping issues on phones.
class JobApplicationFormScreen extends StatefulWidget {
  final String jobTitle;

  const JobApplicationFormScreen({
    super.key,
    required this.jobTitle,
  });

  @override
  State<JobApplicationFormScreen> createState() =>
      _JobApplicationFormScreenState();
}

class _JobApplicationFormScreenState extends State<JobApplicationFormScreen> {
  final _coverController = TextEditingController();
  final _referencesController = TextEditingController();
  final _additionalController = TextEditingController();
  final List<PlatformFile> _qualFiles = [];
  bool _pickingFiles = false;
  static const int _maxFiles = 5;
  static const int _maxBytes = 10 * 1024 * 1024;

  @override
  void dispose() {
    _coverController.dispose();
    _referencesController.dispose();
    _additionalController.dispose();
    super.dispose();
  }

  Future<void> _pickQualificationFiles() async {
    setState(() => _pickingFiles = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;

      final files = result.files.where((f) => f.name.trim().isNotEmpty).toList();
      if (_qualFiles.length + files.length > _maxFiles) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You can attach up to $_maxFiles files.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return;
      }

      for (final f in files) {
        final len = f.size;
        if (len > 0 && len > _maxBytes) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${f.name}" is too large (max 10 MB per file).'),
              backgroundColor: Colors.red.shade800,
            ),
          );
          return;
        }
      }

      setState(() => _qualFiles.addAll(files));
    } finally {
      if (mounted) setState(() => _pickingFiles = false);
    }
  }

  void _removeQualFileAt(int index) {
    setState(() => _qualFiles.removeAt(index));
  }

  void _submit() {
    final cover = _coverController.text.trim();
    final hasCover = cover.length >= 20;
    final hasFiles = _qualFiles.isNotEmpty;

    if (!hasCover && !hasFiles) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a cover letter (at least 20 characters) or attach at least one CV/certificate.',
          ),
          backgroundColor: JobsyColors.error,
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      JobApplicationFormResult(
        coverLetter: _coverController.text,
        referencesText: _referencesController.text,
        additionalInfo: _additionalController.text,
        qualificationFiles: List.from(_qualFiles),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.jobTitle.trim().isEmpty ? 'Job' : widget.jobTitle.trim();

    return Scaffold(
      backgroundColor: JobsyColors.background,
      appBar: AppBar(
        backgroundColor: JobsyColors.background,
        foregroundColor: JobsyColors.textPrimary,
        elevation: 0,
        title: const Text(
          'Apply to job',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: JobsyColors.workerPrimary.withOpacity(0.95),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: JobsyColors.employerPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: JobsyColors.employerPrimary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.tips_and_updates_outlined,
                          color: JobsyColors.employerDark.withValues(alpha: 0.9),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Required: a cover letter (20+ characters) or at least one CV/certificate. References and extra notes are optional but help you stand out.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: JobsyColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Cover letter',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: JobsyColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Required if you don’t attach a CV/certificate.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: JobsyColors.textTertiary.withOpacity(0.95),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _coverController,
                    maxLines: 4,
                    maxLength: 2000,
                    style: const TextStyle(
                      color: JobsyColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Why you’re a good fit, availability, relevant experience…',
                      hintStyle: const TextStyle(
                        color: JobsyColors.textTertiary,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: JobsyColors.surface,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: JobsyColors.border.withOpacity(0.4),
                          width: 0.6,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: JobsyColors.border.withOpacity(0.4),
                          width: 0.6,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: JobsyColors.workerPrimary,
                          width: 1.2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'References (optional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: JobsyColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _referencesController,
                    maxLines: 3,
                    maxLength: 1500,
                    style: const TextStyle(
                      color: JobsyColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Names, how they know your work, phone or email…',
                      hintStyle: const TextStyle(
                        color: JobsyColors.textTertiary,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: JobsyColors.surface,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: JobsyColors.border.withOpacity(0.4),
                          width: 0.6,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: JobsyColors.border.withOpacity(0.4),
                          width: 0.6,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: JobsyColors.workerPrimary,
                          width: 1.2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Qualifications / CV',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: JobsyColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Required if your cover letter is under 20 characters.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: JobsyColors.textTertiary.withOpacity(0.95),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'PDF or images — up to $_maxFiles files, 10 MB each.',
                    style: TextStyle(
                      fontSize: 12,
                      color: JobsyColors.textTertiary.withOpacity(0.95),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickingFiles ? null : _pickQualificationFiles,
                      icon: _pickingFiles
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file_rounded, size: 20),
                      label: Text(
                        _qualFiles.isEmpty
                            ? 'Attach certificates / CV'
                            : '${_qualFiles.length} file(s) selected',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: JobsyColors.workerPrimary,
                        side: BorderSide(
                          color:
                              JobsyColors.workerPrimary.withOpacity(0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (_qualFiles.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_qualFiles.length, (i) {
                        final f = _qualFiles[i];
                        return Chip(
                          label: Text(
                            f.name,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => _removeQualFileAt(i),
                          deleteIconColor: JobsyColors.textSecondary,
                        );
                      }),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Anything else? (optional)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: JobsyColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _additionalController,
                    maxLines: 3,
                    maxLength: 1500,
                    style: const TextStyle(
                      color: JobsyColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Licences, tools, languages, links…',
                      hintStyle: const TextStyle(
                        color: JobsyColors.textTertiary,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: JobsyColors.surface,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: JobsyColors.border.withOpacity(0.4),
                          width: 0.6,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: JobsyColors.border.withOpacity(0.4),
                          width: 0.6,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: JobsyColors.workerPrimary,
                          width: 1.2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: JobsyColors.background,
              border: Border(
                top: BorderSide(
                  color: JobsyColors.border.withOpacity(0.5),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: JobsyColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: JobsyColors.workerFilledButtonStyle(radius: 12),
                      child: const Text(
                        'Submit application',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
