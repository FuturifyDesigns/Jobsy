import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/colors.dart';

/// Optional data the worker can attach when applying (everything optional).
class JobApplicationDraft {
  final String? coverLetter;
  final String? relevantExperience;
  final String? availabilityNote;
  final List<Map<String, String>> references;
  final Uint8List? qualificationBytes;
  final String? qualificationFilename;
  final String? qualificationExt;
  final int qualificationSize;

  const JobApplicationDraft({
    required this.coverLetter,
    required this.relevantExperience,
    required this.availabilityNote,
    required this.references,
    this.qualificationBytes,
    this.qualificationFilename,
    this.qualificationExt,
    this.qualificationSize = 0,
  });
}

class JobApplySheet extends StatefulWidget {
  final String jobTitle;
  final ScrollController scrollController;

  const JobApplySheet({
    super.key,
    required this.jobTitle,
    required this.scrollController,
  });

  static Future<JobApplicationDraft?> show(
    BuildContext context, {
    required String jobTitle,
  }) {
    final scrollController = ScrollController();
    return showModalBottomSheet<JobApplicationDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.55,
          maxChildSize: 0.98,
          expand: false,
          builder: (context, scroll) {
            return JobApplySheet(
              jobTitle: jobTitle,
              scrollController: scroll,
            );
          },
        );
      },
    );
  }

  @override
  State<JobApplySheet> createState() => _JobApplySheetState();
}

class _JobApplySheetState extends State<JobApplySheet> {
  final _cover = TextEditingController();
  final _experience = TextEditingController();
  final _availability = TextEditingController();
  final _refName1 = TextEditingController();
  final _refRel1 = TextEditingController();
  final _refContact1 = TextEditingController();
  final _refName2 = TextEditingController();
  final _refRel2 = TextEditingController();
  final _refContact2 = TextEditingController();

  PlatformFile? _qualFile;

  static const int _maxDocBytes = 5 * 1024 * 1024;

  @override
  void dispose() {
    _cover.dispose();
    _experience.dispose();
    _availability.dispose();
    _refName1.dispose();
    _refRel1.dispose();
    _refContact1.dispose();
    _refName2.dispose();
    _refRel2.dispose();
    _refContact2.dispose();
    super.dispose();
  }

  Future<void> _pickQualificationDoc() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final size = picked.size;
      if (size > _maxDocBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File too large (${(size / 1024 / 1024).toStringAsFixed(1)} MB). Max 5 MB.',
              ),
              backgroundColor: JobsyColors.error,
            ),
          );
        }
        return;
      }
      setState(() => _qualFile = picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not pick file: $e'),
            backgroundColor: JobsyColors.error,
          ),
        );
      }
    }
  }

  List<Map<String, String>> _buildReferencesList() {
    final out = <Map<String, String>>[];
    void add(String name, String rel, String contact) {
      final n = name.trim();
      final c = contact.trim();
      if (n.isEmpty && c.isEmpty && rel.trim().isEmpty) return;
      if (n.isEmpty || c.isEmpty) return;
      out.add({
        'name': n,
        'relationship': rel.trim(),
        'contact': c,
      });
    }
    add(_refName1.text, _refRel1.text, _refContact1.text);
    add(_refName2.text, _refRel2.text, _refContact2.text);
    return out;
  }

  Future<void> _submit() async {
    final refs = _buildReferencesList();
    Uint8List? bytes = _qualFile?.bytes;
    if (bytes == null && _qualFile?.path != null) {
      try {
        bytes = await File(_qualFile!.path!).readAsBytes();
      } catch (_) {}
    }
    final name = _qualFile?.name;
    final ext = (_qualFile?.extension ?? '').toLowerCase();

    if (!mounted) return;
    Navigator.pop(
      context,
      JobApplicationDraft(
        coverLetter: _cover.text.trim().isEmpty ? null : _cover.text.trim(),
        relevantExperience:
            _experience.text.trim().isEmpty ? null : _experience.text.trim(),
        availabilityNote:
            _availability.text.trim().isEmpty ? null : _availability.text.trim(),
        references: refs,
        qualificationBytes: bytes,
        qualificationFilename: name,
        qualificationExt: ext.isEmpty ? null : ext,
        qualificationSize: _qualFile?.size ?? 0,
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: JobsyColors.textTertiary, fontSize: 13),
        filled: true,
        fillColor: JobsyColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: JobsyColors.border.withOpacity(0.4), width: 0.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: JobsyColors.border.withOpacity(0.4), width: 0.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: JobsyColors.workerPrimary, width: 1),
        ),
        contentPadding: const EdgeInsets.all(12),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: JobsyColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: JobsyColors.workerPrimary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_ind_rounded,
                      color: JobsyColors.workerPrimary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Apply to job',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: JobsyColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: JobsyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: JobsyColors.textSecondary),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Employers see everything you add below — it\'s all optional, but more detail helps them decide faster.',
              style: TextStyle(
                fontSize: 12.5,
                color: JobsyColors.textTertiary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _sectionLabel('Cover letter', Icons.edit_note_rounded),
                TextField(
                  controller: _cover,
                  maxLines: 4,
                  style: const TextStyle(
                      color: JobsyColors.textPrimary, fontSize: 14),
                  decoration: _dec('Why you want this job…'),
                ),
                const SizedBox(height: 16),
                _sectionLabel('Relevant experience', Icons.construction_rounded),
                TextField(
                  controller: _experience,
                  maxLines: 4,
                  style: const TextStyle(
                      color: JobsyColors.textPrimary, fontSize: 14),
                  decoration: _dec(
                      'Similar jobs, certifications, years in trade, tools you use…'),
                ),
                const SizedBox(height: 16),
                _sectionLabel('Availability', Icons.event_available_rounded),
                TextField(
                  controller: _availability,
                  maxLines: 2,
                  style: const TextStyle(
                      color: JobsyColors.textPrimary, fontSize: 14),
                  decoration: _dec('When you can start, days/times that work…'),
                ),
                const SizedBox(height: 16),
                _sectionLabel(
                    'Qualification document', Icons.workspace_premium_rounded),
                Text(
                  'PDF or photo of a certificate, licence, or ID (max 5 MB).',
                  style: TextStyle(
                    fontSize: 12,
                    color: JobsyColors.textTertiary.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickQualificationDoc,
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: Text(_qualFile == null
                      ? 'Attach file'
                      : _qualFile!.name),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: JobsyColors.workerPrimary,
                    side: BorderSide(
                        color: JobsyColors.workerPrimary.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (_qualFile != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _qualFile = null),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove file'),
                    ),
                  ),
                const SizedBox(height: 20),
                _sectionLabel('References (optional)', Icons.people_outline_rounded),
                Text(
                  'Up to two previous employers or clients who can vouch for you. Name and contact are required for each row you use.',
                  style: TextStyle(
                    fontSize: 12,
                    color: JobsyColors.textTertiary.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 10),
                _referenceBlock(
                  'Reference 1',
                  _refName1,
                  _refRel1,
                  _refContact1,
                ),
                const SizedBox(height: 12),
                _referenceBlock(
                  'Reference 2',
                  _refName2,
                  _refRel2,
                  _refContact2,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: JobsyColors.workerFilledButtonStyle(radius: 14),
                    child: const Text(
                      'Submit application',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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

  Widget _sectionLabel(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: JobsyColors.workerPrimary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: JobsyColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _referenceBlock(
    String label,
    TextEditingController name,
    TextEditingController relationship,
    TextEditingController contact,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JobsyColors.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JobsyColors.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: JobsyColors.textPrimary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            style: const TextStyle(color: JobsyColors.textPrimary, fontSize: 14),
            decoration: _dec('Full name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: relationship,
            style: const TextStyle(color: JobsyColors.textPrimary, fontSize: 14),
            decoration: _dec('Relationship (e.g. Site manager at…)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: contact,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: JobsyColors.textPrimary, fontSize: 14),
            decoration: _dec('Phone or email'),
          ),
        ],
      ),
    );
  }
}
