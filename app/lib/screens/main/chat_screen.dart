import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/plan_badge.dart';
import 'convert_account_screen.dart';

/// The single public chat room.
///
/// Every posting rule lives in the database (`chat_before_insert`): links are
/// admin-only, guests cannot post, mutes and the rate limit are checked there. This
/// screen does not duplicate any of them — it shows what the server said. The two
/// exceptions are refusals worth making *before* the round trip: a guest gets the
/// upgrade prompt instead of a composer, and a muted user is told up front rather
/// than after typing a message.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  List<ChatMessage> _messages = const [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  DateTime? _mutedUntil;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Leaving the channel open would keep a websocket subscription alive for the
    // rest of the session, on every visit to the room.
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _isGuest => context.read<AuthService>().isGuest;

  Future<void> _load() async {
    final messages = await ChatService.instance.loadRecent();
    // A guest cannot post, so their mute state is irrelevant and the lookup is
    // skipped rather than spending a request to learn nothing.
    final muted = _isGuest ? null : await ChatService.instance.myMutedUntil();
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _mutedUntil = muted;
      _loading = false;
    });
    _jumpToEnd();

    _channel ??= ChatService.instance.subscribe((id) async {
      // Realtime carries the raw row with no author, so the joined version is
      // fetched. Cheap: one row, and only for messages that actually arrive.
      if (_messages.any((m) => m.id == id)) return;
      final message = await ChatService.instance.fetchOne(id);
      if (message == null || !mounted) return;
      final atEnd = !_scroll.hasClients ||
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80;
      setState(() => _messages = [..._messages, message]);
      // Only follow the conversation if the user was already at the bottom.
      // Yanking the view down while someone reads history is worse than a missed
      // message.
      if (atEnd) _jumpToEnd();
    });
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendText() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await ChatService.instance.sendText(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      _tell(error);
      return;
    }
    // Cleared only on success, so a refused message is not lost and can be edited.
    _controller.clear();
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Compressed on device, as specified. The bucket caps uploads at 5 MB and
      // rejects anything larger, so this is what keeps a modern phone photo inside
      // the limit rather than failing at the end of an upload.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() => _sending = true);
    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    final error = await ChatService.instance.sendImage(
      bytes: bytes,
      extension: ext.isEmpty ? 'jpg' : ext,
      caption: _controller.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      _tell(error);
      return;
    }
    _controller.clear();
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final auth = context.read<AuthService>();
    final isAdmin = auth.user?.isAdmin == true;
    final isMine = message.userId == auth.user?.id;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            if (!isMine)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.bear),
                title: Text('Report this message',
                    style: GoogleFonts.inter(fontSize: 15, color: AppColors.ink)),
                onTap: () async {
                  Navigator.pop(sheet);
                  final ok = await ChatService.instance.report(message.id);
                  _tell(ok
                      ? 'Reported. Thanks — an admin will take a look.'
                      : 'That report could not be sent.');
                },
              ),
            if (isAdmin) ...[
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.bear),
                title: Text('Delete message',
                    style: GoogleFonts.inter(fontSize: 15, color: AppColors.ink)),
                onTap: () async {
                  Navigator.pop(sheet);
                  final ok = await ChatService.instance.deleteMessage(message.id);
                  if (ok && mounted) {
                    setState(() => _messages =
                        _messages.where((m) => m.id != message.id).toList());
                  }
                  _tell(ok ? 'Message removed.' : 'That could not be removed.');
                },
              ),
              if (!isMine)
                ListTile(
                  leading:
                      const Icon(Icons.volume_off_outlined, color: AppColors.bear),
                  title: Text('Mute this user for 1 day',
                      style:
                          GoogleFonts.inter(fontSize: 15, color: AppColors.ink)),
                  onTap: () async {
                    Navigator.pop(sheet);
                    final until =
                        await ChatService.instance.muteUser(message.userId);
                    _tell(until == null
                        ? 'That user could not be muted.'
                        : 'Muted until ${_stamp(until)}.');
                  },
                ),
            ],
            ListTile(
              leading: Icon(Icons.close, color: AppColors.ink4),
              title: Text('Cancel',
                  style: GoogleFonts.inter(fontSize: 15, color: AppColors.ink3)),
              onTap: () => Navigator.pop(sheet),
            ),
          ],
        ),
      ),
    );
  }

  static String _stamp(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.parchment,
        centerTitle: false,
        title: Text('Titans Room',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold, color: AppColors.ink)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'Nothing here yet. Say hello.',
                            style: GoogleFonts.inter(
                                fontSize: 14, color: AppColors.ink4),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _bubble(_messages[i]),
                      ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage message) {
    final isMine =
        message.userId == context.read<AuthService>().user?.id;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(message),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isMine ? AppColors.goldLight : AppColors.pureWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.birch),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.authorName ?? 'Titan',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink3),
                    ),
                    if (message.authorTier != null &&
                        message.authorTier != 'free') ...[
                      const SizedBox(width: 4),
                      PlanBadge(tier: message.authorTier!, compact: true),
                    ],
                  ],
                ),
              if (message.isImage && message.mediaPath != null)
                _media(message.mediaPath!),
              if (message.isVoice)
                // The server and the schema already accept voice notes. The client
                // cannot record one yet: that needs microphone permission, which
                // the privacy policy currently promises we do not ask for. Rendered
                // as unsupported rather than dropped, so a message posted by a
                // future build does not silently vanish here.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_none, size: 16, color: AppColors.ink4),
                      const SizedBox(width: 4),
                      Text('Voice note — update the app to play',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.ink4)),
                    ],
                  ),
                ),
              if (message.body != null && message.body!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    message.body!,
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppColors.ink, height: 1.35),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(_stamp(message.createdAt),
                    style: GoogleFonts.inter(
                        fontSize: 10, color: AppColors.ink5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Chat media lives in a private bucket, so each image needs a signed URL.
  Widget _media(String path) {
    return FutureBuilder<String?>(
      future: ChatService.instance.mediaUrl(path),
      builder: (_, snap) {
        if (snap.data == null) {
          return const SizedBox(
            height: 160,
            width: 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: AppNetworkImage(url: snap.data!, height: 180),
          ),
        );
      },
    );
  }

  /// The composer, or the reason there isn't one.
  ///
  /// Guests get the upgrade prompt rather than a disabled text field: a guest
  /// account cannot be recovered, so the useful action is converting it, not
  /// explaining a greyed-out control. Same reasoning as subscribe_screen, which
  /// stops a guest before the money rather than after.
  Widget _composer() {
    if (context.watch<AuthService>().isGuest) return _guestPrompt();

    final muted = _mutedUntil;
    if (muted != null) {
      return _notice(
        icon: Icons.volume_off_outlined,
        text: 'You are muted until ${_stamp(muted)} and cannot post right now.',
      );
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          border: Border(top: BorderSide(color: AppColors.birch)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.image_outlined, color: AppColors.ink3),
              tooltip: 'Send a photo',
              onPressed: _sending ? null : _sendImage,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Message the room',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send_rounded,
                  color: _sending ? AppColors.ink5 : AppColors.imperialGold),
              tooltip: 'Send',
              onPressed: _sending ? null : _sendText,
            ),
          ],
        ),
      ),
    );
  }

  Widget _guestPrompt() {
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          border: Border(top: BorderSide(color: AppColors.birch)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_open_outlined, size: 18, color: AppColors.ink3),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Make your account permanent to chat',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'You can read the room as a guest. Posting needs a permanent '
              'account, which also means your portfolio and history survive a '
              'reinstall.',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.ink4, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ConvertAccountScreen()),
                ),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: Text('Make account permanent',
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppColors.imperialGold,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice({required IconData icon, required String text}) {
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          border: Border(top: BorderSide(color: AppColors.birch)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.ink4),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.ink3, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
