import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../screens/main/community_wishlist_screen.dart';
import '../services/supabase_service.dart';

/// The "Request a Feature" sheet.
///
/// Moved out of `profile_screen.dart` unchanged, because a notification can now
/// open it too — `cta_route: 'feature'` lands here. It was a private method on the
/// profile screen's State, so the only way to reach it was the profile menu, and a
/// notification promising ₹2,000 for an idea had nowhere to send anyone.
///
/// Moved rather than copied: two sheets that submit feature requests would drift,
/// and the duplicate-detection lookup below is the kind of thing that gets fixed in
/// one copy and not the other.
Future<void> showRequestFeatureSheet(BuildContext context) {
  final titleController = TextEditingController();
  final descController = TextEditingController();
  XFile? pickedImage;
  Uint8List? pickedBytes;
  bool submitting = false;
  List<Map<String, dynamic>> similarFeatures = [];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.pureWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
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
              Text('Request a Feature',
                  style: GoogleFonts.inter(
                      fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text('Tell us what we should build next!',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.ink4)),
              const SizedBox(height: AppSpacing.md),

              Text('Feature Title',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
              const SizedBox(height: 6),
              TextField(
                controller: titleController,
                onChanged: (val) async {
                  if (val.trim().length >= 5) {
                    final results =
                        await SupabaseService().searchSimilarFeatures(val.trim());
                    setModalState(() => similarFeatures = results);
                  } else {
                    setModalState(() => similarFeatures = []);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Enter feature name...',
                  hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                  border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.imperialGold)),
                ),
              ),
              if (similarFeatures.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.goldPale,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.goldBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Similar requests found. Upvote instead?',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink)),
                      const SizedBox(height: 6),
                      ...similarFeatures.map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('- ${f['title']}',
                                      style: GoogleFonts.inter(
                                          fontSize: 12, color: AppColors.ink3),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => const CommunityWishlistScreen()));
                                  },
                                  child: Text('View & Upvote',
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.imperialGold)),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              Text('Description',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
              const SizedBox(height: 6),
              TextField(
                controller: descController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Describe the feature in detail...',
                  hintStyle: GoogleFonts.inter(color: AppColors.ink5),
                  border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.birch)),
                  focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.imperialGold)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              Text('Attach an Image (Optional)',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.ink2)),
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
                        image: MemoryImage(pickedBytes!), fit: BoxFit.cover),
                  ),
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () => setModalState(() {
                      pickedImage = null;
                      pickedBytes = null;
                    }),
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
                  label: Text('Select Image',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    side: BorderSide(color: AppColors.birch),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md)),
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
                              const SnackBar(
                                  content: Text(
                                      'Please fill in both title and description.')),
                            );
                            return;
                          }
                          if (title.length < 5 || desc.length < 10) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Title must be at least 5 chars, Description at least 10 chars.')),
                            );
                            return;
                          }

                          setModalState(() => submitting = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            String? imageUrl;
                            if (pickedImage != null && pickedBytes != null) {
                              imageUrl = await SupabaseService()
                                  .uploadTicketAttachment(pickedImage!.path, pickedBytes!);
                            }
                            await SupabaseService().submitFeatureRequest(
                              title: title,
                              description: desc,
                              imageUrl: imageUrl,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              messenger.showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Thank you! Your feature request has been submitted to the wishlist.')),
                              );
                            }
                          } catch (e) {
                            setModalState(() => submitting = false);
                            messenger.showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Error: ${e.toString().replaceAll("Exception:", "")}')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.imperialGold,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: submitting
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.pureWhite, strokeWidth: 2),
                        )
                      : Text('Submit',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, color: AppColors.pureWhite)),
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
