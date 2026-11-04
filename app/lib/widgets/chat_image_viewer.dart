import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'app_network_image.dart';

/// A full-screen, WhatsApp-style interactive image viewer for chat attachments.
/// Features:
/// - Pinch-to-zoom (up to 4x) & panning via [InteractiveViewer]
/// - Double-tap to quickly zoom in / reset
/// - Immersive black background with translucent top & bottom controls
/// - Sender attribution, formatted timestamp, and optional caption
class ChatImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? caption;
  final String? authorName;
  final DateTime? timestamp;

  const ChatImageViewer({
    super.key,
    required this.imageUrl,
    this.caption,
    this.authorName,
    this.timestamp,
  });

  static Future<void> show(
    BuildContext context, {
    required String imageUrl,
    String? caption,
    String? authorName,
    DateTime? timestamp,
  }) {
    HapticFeedback.lightImpact();
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black,
        pageBuilder: (context, anim, _) => FadeTransition(
          opacity: anim,
          child: ChatImageViewer(
            imageUrl: imageUrl,
            caption: caption,
            authorName: authorName,
            timestamp: timestamp,
          ),
        ),
      ),
    );
  }

  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  final TransformationController _transformController = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _showOverlays = true;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformController.value = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0.0, 1.0)
        ..scaleByDouble(2.5, 2.5, 1.0, 1.0);
    }
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
    final timeStr = DateFormat('hh:mm a').format(local);
    if (isToday) return 'Today at $timeStr';
    return '${DateFormat('dd MMM, ').format(local)}$timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.authorName ?? 'Shared Photo';
    final subtitle = _formatTimestamp(widget.timestamp);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Zoomable Image
          GestureDetector(
            onTap: () => setState(() => _showOverlays = !_showOverlays),
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: _handleDoubleTap,
            child: SizedBox.expand(
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: AppNetworkImage(
                    url: widget.imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          // Top Header Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showOverlays ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 6,
                bottom: 12,
                left: 8,
                right: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              color: const Color(0xFFCBD5E1),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Caption Bar
          if (widget.caption != null && widget.caption!.trim().isNotEmpty)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _showOverlays ? 0 : -120,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 14,
                  top: 14,
                  left: 20,
                  right: 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.90),
                      Colors.black.withValues(alpha: 0.60),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  widget.caption!,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14.5,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
