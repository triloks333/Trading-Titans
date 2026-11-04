import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../services/supabase_service.dart';

/// The "Report an Issue" sheet.
///
/// Moved out of `profile_screen.dart` unchanged, like request_feature_sheet.dart,
/// so the home carousel can open it as well as the profile menu.
Future<void> showReportIssueSheet(BuildContext context) {
  final titleController = TextEditingController();
  final descController = TextEditingController();
  XFile? pickedImage;
  Uint8List? pickedBytes;
  bool submitting = false;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.pureWhite,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: AppSpacing.lg,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report an Issue', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text('Encountered a bug? Let us know so we can fix it.', style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
              const SizedBox(height: AppSpacing.md),
              
              Text('Issue Title', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
              const SizedBox(height: 6),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  hintText: 'Enter issue name...',
                  hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                  border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              
              Text('Description', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
              const SizedBox(height: 6),
              TextField(
                controller: descController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Describe the bug or issue...',
                  hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                  border:       OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.imperialGold)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              
              Text('Attach an Image (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
              const SizedBox(height: 6),
              if (pickedBytes != null)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.birch),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    image: DecorationImage(
                      image: MemoryImage(pickedBytes!),
                      fit: BoxFit.cover,
                    ),
                  ),
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () {
                      setModalState(() {
                        pickedImage = null;
                        pickedBytes = null;
                      });
                    },
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      final bytes = await image.readAsBytes();
                      setModalState(() {
                        pickedImage = image;
                        pickedBytes = bytes;
                      });
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text('Select Image', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    side:       BorderSide(color: AppColors.birch),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                ),
              
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          final desc = descController.text.trim();
                          if (title.isEmpty || desc.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please fill in both title and description.')),
                            );
                            return;
                          }
                          
                          setModalState(() => submitting = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            String? imageUrl;
                            if (pickedImage != null && pickedBytes != null) {
                              imageUrl = await SupabaseService().uploadTicketAttachment(pickedImage!.path, pickedBytes!);
                            }
                            await SupabaseService().submitSupportTicket(
                              type: 'issue',
                              title: title,
                              content: desc,
                              imageUrl: imageUrl,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Thank you! Our engineering team will review the issue.')),
                              );
                            }
                          } catch (e) {
                            setModalState(() => submitting = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('Error submitting report: $e')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.imperialGold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: submitting
                      ?       SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: AppColors.pureWhite, strokeWidth: 2),
                        )
                      : Text('Submit Report', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    ),
  );
}
