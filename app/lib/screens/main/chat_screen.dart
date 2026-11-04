import 'dart:async';

import 'package:flutter/material.dart';
import 'community_wishlist_screen.dart';
import 'support_tickets_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/chat_image_viewer.dart';
import '../../widgets/chat_route_card.dart';
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
  /// 0 Room, 1 Tickets, 2 Wishlist.
  const ChatScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _deletedForMePrefsKey = 'chat_deleted_for_me_ids';

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focusNode = FocusNode();

  List<ChatMessage> _messages = const [];
  Set<String> _deletedForMeIds = {};
  ChatMessage? _editingMessage;
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  DateTime? _mutedUntil;

  // Admin tagging & slash command states
  bool _isChatNotificationsMuted = false;
  bool _showMentionOverlay = false;
  bool _showSlashOverlay = false;
  String _mentionQuery = '';
  String _slashQuery = '';
  List<ChatTaggableUser> _taggableUsers = const [];
  String? _selectedActionRoute;
  Timer? _mentionDebounce;

  @override
  void initState() {
    super.initState();
    ChatService.isChatRoomActive = true;
    _controller.addListener(_onTextChanged);
    _initDeletedForMe();
    _checkMuteStatus();
    _load();
  }

  @override
  void dispose() {
    ChatService.isChatRoomActive = false;
    _mentionDebounce?.cancel();
    _controller.removeListener(_onTextChanged);
    // Leaving the channel open would keep a websocket subscription alive for the
    // rest of the session, on every visit to the room.
    final channel = _channel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    _controller.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initDeletedForMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_deletedForMePrefsKey) ?? [];
      if (mounted) {
        setState(() {
          _deletedForMeIds = list.toSet();
        });
      }
    } catch (e) {
      debugPrint('Failed to load deleted-for-me ids: $e');
    }
  }

  Future<void> _deleteForMe(String messageId) async {
    final nextSet = Set<String>.from(_deletedForMeIds)..add(messageId);
    setState(() {
      _deletedForMeIds = nextSet;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_deletedForMePrefsKey, nextSet.toList());
      _tell('Message hidden for you.');
    } catch (e) {
      debugPrint('Failed to persist deleted-for-me: $e');
    }
  }

  bool get _isGuest => context.read<AuthService>().isGuest;

  List<ChatMessage> get _displayMessages =>
      _messages.where((m) => !_deletedForMeIds.contains(m.id)).toList();

  Future<void> _load() async {
    final rawMessages = await ChatService.instance.loadRecent();
    // A guest cannot post, so their mute state is irrelevant and the lookup is
    // skipped rather than spending a request to learn nothing.
    final muted = _isGuest ? null : await ChatService.instance.myMutedUntil();
    if (!mounted) return;

    // Ordered newest-first so ListView.builder(reverse: true) places offset 0.0
    // natively at the bottom without jumping or layout glitches.
    setState(() {
      _messages = rawMessages.reversed.toList();
      _mutedUntil = muted;
      _loading = false;
    });

    _channel ??= ChatService.instance.subscribe((id) async {
      // Check if this is an update to an existing message (e.g. edit)
      final existingIndex = _messages.indexWhere((m) => m.id == id);
      final updated = await ChatService.instance.fetchOne(id);
      if (updated == null || !mounted) return;

      setState(() {
        if (existingIndex != -1) {
          final updatedList = List<ChatMessage>.from(_messages);
          updatedList[existingIndex] = updated;
          _messages = updatedList;
        } else {
          // Prepend newest message at index 0
          _messages = [updated, ..._messages];
        }
      });
    });
  }

  void _tell(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _startEditing(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _controller.text = message.body ?? '';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessage = null;
    });
    _controller.clear();
  }

  Future<void> _checkMuteStatus() async {
    final muted = await ChatService.isChatMuted();
    if (mounted) setState(() => _isChatNotificationsMuted = muted);
  }

  void _hideOverlays() {
    if (_showMentionOverlay || _showSlashOverlay) {
      setState(() {
        _showMentionOverlay = false;
        _showSlashOverlay = false;
      });
    }
  }

  void _onTextChanged() {
    final auth = context.read<AuthService>();
    final isAdmin = auth.user?.isAdmin == true;
    if (!isAdmin) {
      _hideOverlays();
      return;
    }

    final text = _controller.text;
    final selection = _controller.selection;
    final cursor = selection.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      _hideOverlays();
      return;
    }

    final textBeforeCursor = text.substring(0, cursor);
    final mentionMatch =
        RegExp(r'@([a-zA-Z0-9_\-\.]*)$').firstMatch(textBeforeCursor);
    final slashMatch =
        RegExp(r'/([a-zA-Z0-9_\-]*)$').firstMatch(textBeforeCursor);

    if (mentionMatch != null) {
      final query = mentionMatch.group(1) ?? '';
      _mentionQuery = query;
      if (!_showMentionOverlay) {
        setState(() {
          _showMentionOverlay = true;
          _showSlashOverlay = false;
        });
      }
      _searchUsers(query);
    } else if (slashMatch != null) {
      final query = slashMatch.group(1) ?? '';
      setState(() {
        _slashQuery = query.toLowerCase();
        _showSlashOverlay = true;
        _showMentionOverlay = false;
      });
    } else {
      _hideOverlays();
    }
  }

  void _searchUsers(String query) {
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(const Duration(milliseconds: 180), () async {
      final results = await ChatService.instance.getTaggableUsers(query);
      if (mounted) {
        setState(() {
          _taggableUsers = results;
        });
      }
    });
  }

  void _insertMention(String mentionText) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final textBeforeCursor = cursor >= 0 && cursor <= text.length
        ? text.substring(0, cursor)
        : text;
    final textAfterCursor = cursor >= 0 && cursor <= text.length
        ? text.substring(cursor)
        : '';

    final match =
        RegExp(r'@([a-zA-Z0-9_\-\.]*)$').firstMatch(textBeforeCursor);
    if (match != null) {
      final start = match.start;
      final newPrefix =
          '${textBeforeCursor.substring(0, start)}@$mentionText ';
      final newText = newPrefix + textAfterCursor;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newPrefix.length),
      );
    } else {
      _controller.text = '$text@$mentionText ';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
    _hideOverlays();
    _focusNode.requestFocus();
  }

  void _insertSlashCommand(ChatRouteMeta meta) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final textBeforeCursor = cursor >= 0 && cursor <= text.length
        ? text.substring(0, cursor)
        : text;
    final textAfterCursor = cursor >= 0 && cursor <= text.length
        ? text.substring(cursor)
        : '';

    final match =
        RegExp(r'/([a-zA-Z0-9_\-]*)$').firstMatch(textBeforeCursor);
    if (match != null) {
      final start = match.start;
      final newPrefix =
          '${textBeforeCursor.substring(0, start)}${meta.slashCommand} ';
      final newText = newPrefix + textAfterCursor;
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newPrefix.length),
      );
    } else {
      _controller.text = '$text${meta.slashCommand} ';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
    _selectedActionRoute = meta.slashCommand;
    _hideOverlays();
    _focusNode.requestFocus();
  }

  /// Chat notification controls: unmute, or mute for 8h / 1 day / 1 week.
  /// @everyone priority alerts and direct mentions always get through.
  Future<void> _showNotificationMuteSheet() async {
    final isMuted = await ChatService.isChatMuted();
    if (!mounted) return;
    Future<void> act(BuildContext sheet, Future<void> Function() change, String told) async {
      Navigator.pop(sheet);
      await change();
      await _checkMuteStatus();
      _tell(told);
    }

    const options = [
      (Icons.timer_outlined, 'Mute for 8 hours', Duration(hours: 8), 'Muted for 8 hours. (@everyone will still alert you)'),
      (Icons.bedtime_outlined, 'Mute for 1 day', Duration(days: 1), 'Muted for 1 day.'),
      (Icons.volume_mute_outlined, 'Mute for 1 week', Duration(days: 7), 'Muted for 1 week.'),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Chat notifications', style: AppFonts.sans(size: 18, weight: FontWeight.w700, color: AppColors.ink)),
              Text(isMuted ? 'Muted' : 'Active: tray alerts for new messages', style: AppText.bodySmall),
            ]),
          ),
          ListTile(
            leading: Icon(Icons.notifications_active_outlined, color: AppColors.goldMid),
            title: Text('All messages', style: AppText.bodyBold),
            subtitle: Text('Receive tray alerts for all community messages', style: AppText.bodySmall),
            trailing: isMuted ? null : Icon(Icons.check_rounded, color: AppColors.goldMid),
            onTap: () => isMuted
                ? act(sheet, ChatService.unmuteNotifications, 'Notifications unmuted.')
                : Navigator.pop(sheet),
          ),
          for (final (icon, label, d, told) in options)
            ListTile(
              leading: Icon(icon, color: AppColors.ink3),
              title: Text(label, style: AppText.bodyBold),
              onTap: () => act(sheet, () => ChatService.muteNotificationsFor(d), told),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: AppCard.badge(AppColors.titanGoldSoft),
            child: Row(children: [
              Icon(Icons.campaign_rounded, size: 16, color: AppColors.titanGold),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('@everyone priority alerts and direct @mentions still notify you.',
                    style: AppFonts.sans(size: 12, color: AppColors.titanGold)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _mentionOverlayWidget() {
    final matchesQuery = _mentionQuery.toLowerCase();
    final showEveryone =
        'everyone'.contains(matchesQuery) || matchesQuery.isEmpty;

    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        border: Border(
          top: BorderSide(color: AppColors.birch, width: 1.2),
          bottom: BorderSide(color: AppColors.birch, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.alternate_email_rounded,
                    size: 14, color: AppColors.imperialGold),
                const SizedBox(width: 6),
                Text(
                  'TAG A MEMBER · ADMIN ONLY',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.imperialGold,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _hideOverlays,
                  child:
                      Icon(Icons.close, size: 16, color: AppColors.ink4),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (showEveryone)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 2),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.imperialGold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.imperialGold
                                .withValues(alpha: 0.4)),
                      ),
                      child: Center(
                        child: Icon(Icons.workspace_premium,
                            size: 18, color: AppColors.imperialGold),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          '@everyone',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.imperialGold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.imperialGold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'BYPASSES MUTE',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Notify every member immediately',
                      style: GoogleFonts.ibmPlexSans(
                          fontSize: 11, color: AppColors.ink4),
                    ),
                    onTap: () => _insertMention('everyone'),
                  ),
                ..._taggableUsers.map(
                  (u) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 1),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: u.isAdmin
                          ? AppColors.imperialGold.withValues(alpha: 0.2)
                          : const Color(0xFF6366F1).withValues(alpha: 0.15),
                      child: Text(
                        u.name.isNotEmpty ? u.name[0].toUpperCase() : 'T',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: u.isAdmin
                              ? AppColors.imperialGold
                              : AppColors.violet,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          '@${u.name}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        if (u.isAdmin) ...[
                          const SizedBox(width: 6),
                          _adminTag(),
                        ],
                      ],
                    ),
                    onTap: () => _insertMention(u.name),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slashOverlayWidget() {
    final query = _slashQuery.replaceAll('/', '').toLowerCase();
    final matchingRoutes = ChatRouteMeta.registry.where((r) {
      final cmd = r.slashCommand.toLowerCase().replaceAll('/', '');
      final title = r.title.toLowerCase();
      return cmd.contains(query) || title.contains(query);
    }).toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        border: Border(
          top: BorderSide(color: AppColors.birch, width: 1.2),
          bottom: BorderSide(color: AppColors.birch, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.link_rounded,
                    size: 15, color: AppColors.imperialGold),
                const SizedBox(width: 6),
                Text(
                  'ATTACH APP PAGE · ADMIN ONLY',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.imperialGold,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _hideOverlays,
                  child:
                      Icon(Icons.close, size: 16, color: AppColors.ink4),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (matchingRoutes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'No matching app pages found for "/$query"',
                style: GoogleFonts.ibmPlexSans(fontSize: 12, color: AppColors.ink4),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: matchingRoutes.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1, color: AppColors.birch.withValues(alpha: 0.5)),
                itemBuilder: (_, i) {
                  final route = matchingRoutes[i];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 3),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: route.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          Icon(route.icon, size: 18, color: route.accentColor),
                    ),
                    title: Row(
                      children: [
                        Text(
                          route.slashCommand,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.goldDeep,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            route.title,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      route.subtitle,
                      style: GoogleFonts.ibmPlexSans(
                          fontSize: 10.5, color: AppColors.ink4),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: AppColors.ink4),
                    onTap: () => _insertSlashCommand(route),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;

    // Handle Edit Mode
    if (_editingMessage != null) {
      final msgToEdit = _editingMessage!;
      if (text.trim() == (msgToEdit.body ?? '').trim()) {
        _cancelEditing();
        return;
      }
      setState(() => _sending = true);
      final error =
          await ChatService.instance.editMessage(msgToEdit.id, text.trim());
      if (!mounted) return;
      setState(() => _sending = false);
      if (error != null) {
        _tell(error);
        return;
      }
      // Update local state immediately for snappy response
      final idx = _messages.indexWhere((m) => m.id == msgToEdit.id);
      if (idx != -1) {
        final current = _messages[idx];
        final updated = ChatMessage(
          id: current.id,
          userId: current.userId,
          kind: current.kind,
          createdAt: current.createdAt,
          body: text.trim(),
          mediaPath: current.mediaPath,
          durationMs: current.durationMs,
          authorName: current.authorName,
          authorTier: current.authorTier,
          authorIsAdmin: current.authorIsAdmin,
          editedAt: DateTime.now().toUtc(),
          actionRoute: current.actionRoute,
        );
        setState(() {
          final copy = List<ChatMessage>.from(_messages);
          copy[idx] = updated;
          _messages = copy;
        });
      }
      _cancelEditing();
      _tell('Message edited.');
      return;
    }

    // Normal Send Mode
    setState(() => _sending = true);
    // Resolve action route either from selected command or by scanning text
    final explicitRoute = _selectedActionRoute;
    final detectedRoute =
        ChatRouteMeta.find(explicitRoute, text)?.slashCommand;
    final error = await ChatService.instance
        .sendText(text, actionRoute: detectedRoute);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      _tell(error);
      return;
    }
    _selectedActionRoute = null;
    _hideOverlays();
    // Cleared only on success, so a refused message is not lost and can be edited.
    _controller.clear();
  }

  Future<void> _sendImage() async {
    if (_sending) return;
    if (_editingMessage != null) _cancelEditing();

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
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMine && message.kind == 'text')
              ListTile(
                leading:
                    Icon(Icons.edit_outlined, color: AppColors.imperialGold),
                title: Text('Edit message',
                    style:
                        GoogleFonts.ibmPlexSans(fontSize: 15, color: AppColors.ink)),
                onTap: () {
                  Navigator.pop(sheet);
                  _startEditing(message);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_sweep_outlined,
                  color: AppColors.ink3),
              title: Text('Delete for me',
                  style:
                      GoogleFonts.ibmPlexSans(fontSize: 15, color: AppColors.ink)),
              subtitle: Text('Hide this message on your device',
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 12, color: AppColors.ink4)),
              onTap: () async {
                Navigator.pop(sheet);
                await _deleteForMe(message.id);
              },
            ),
            if (!isMine)
              ListTile(
                leading: Icon(Icons.flag_outlined, color: AppColors.bear),
                title: Text('Report this message',
                    style:
                        GoogleFonts.ibmPlexSans(fontSize: 15, color: AppColors.ink)),
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
                leading: Icon(Icons.delete_outline, color: AppColors.bear),
                title: Text('Delete for everyone',
                    style: AppFonts.sans(size: 15, weight: FontWeight.w500, color: AppColors.bear)),
                onTap: () async {
                  Navigator.pop(sheet);
                  final ok =
                      await ChatService.instance.deleteMessage(message.id);
                  if (ok && mounted) {
                    setState(() => _messages =
                        _messages.where((m) => m.id != message.id).toList());
                  }
                  _tell(ok ? 'Message removed.' : 'That could not be removed.');
                },
              ),
              if (!isMine)
                ListTile(
                  leading: Icon(Icons.volume_off_outlined, color: AppColors.titanGold),
                  title: Text('Mute this user for 1 day',
                      style: AppFonts.sans(size: 15, weight: FontWeight.w500, color: AppColors.titanGold)),
                  subtitle: Text('Admin only', style: AppText.bodySmall),
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
                  style:
                      GoogleFonts.ibmPlexSans(fontSize: 15, color: AppColors.ink3)),
              onTap: () => Navigator.pop(sheet),
            ),
          ],
        ),
      ),
    );
  }

  /// Marks a message as coming from the Trading Titans team.
  Widget _adminTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.imperialGold,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'ADMIN',
        style: GoogleFonts.ibmPlexSans(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
      ),
    );
  }

  static String _stamp(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _dateChipLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(target).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7 && diffDays > 1) {
      return DateFormat('EEEE').format(local);
    }
    return DateFormat('MMM d, yyyy').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _displayMessages;

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        backgroundColor: AppColors.parchment,
        centerTitle: false,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Titans Room',
              style: GoogleFonts.ibmPlexSans(
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppColors.bull.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.bull.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.bull,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4.5),
                  Text(
                    'Live',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.bull,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isChatNotificationsMuted
                  ? Icons.notifications_off_rounded
                  : Icons.notifications_active_outlined,
              color: _isChatNotificationsMuted
                  ? AppColors.bear
                  : AppColors.imperialGold,
              size: 22,
            ),
            tooltip: _isChatNotificationsMuted
                ? 'Chat notifications muted (tap to change)'
                : 'Chat notifications active (tap to mute)',
            onPressed: _showNotificationMuteSheet,
          ),
          const SizedBox(width: 4),
        ],
        bottom: const TabBar(tabs: [Tab(text: 'Room'), Tab(text: 'Tickets'), Tab(text: 'Wishlist')]),
      ),
      // Tickets and the wishlist live here so community and support share one home.
      body: TabBarView(physics: const NeverScrollableScrollPhysics(), children: [Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : displayList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            'Nothing here yet. Say hello.',
                            style: GoogleFonts.ibmPlexSans(
                                fontSize: 14, color: AppColors.ink4),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true, // Opens directly at newest messages at the bottom
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: displayList.length,
                        itemBuilder: (_, i) {
                          final message = displayList[i];
                          // In newest-first order, index i+1 is the chronologically preceding message
                          final previous = (i + 1 < displayList.length)
                              ? displayList[i + 1]
                              : null;

                          // Date divider logic: check if day changed from chronologically preceding message
                          final bool isNewDay = previous == null ||
                              message.createdAt.year != previous.createdAt.year ||
                              message.createdAt.month != previous.createdAt.month ||
                              message.createdAt.day != previous.createdAt.day;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // In reverse ListView, the preceding header appears above the item
                              if (isNewDay)
                                Center(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.sm),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.birch.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _dateChipLabel(message.createdAt),
                                      style: GoogleFonts.ibmPlexSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink3,
                                      ),
                                    ),
                                  ),
                                ),
                              _bubble(message, previous: previous),
                            ],
                          );
                        },
                      ),
          ),
          if (_showMentionOverlay) _mentionOverlayWidget(),
          if (_showSlashOverlay) _slashOverlayWidget(),
          _composer(),
        ],
      ),
        const SupportTicketsScreen(embedded: true),
        const CommunityWishlistScreen(embedded: true),
      ]),
    ));
  }

  Widget _bubble(ChatMessage message, {ChatMessage? previous}) {
    final auth = context.read<AuthService>();
    final isMine = message.userId == auth.user?.id;
    // Your own messages carry no name, the same as WhatsApp: you know who you are.
    final showAuthor = !isMine && previous?.userId != message.userId;
    final body = message.body ?? '';
    final me = (auth.user?.name ?? '').toLowerCase();
    final isAnnouncement = !isMine && body.contains('@everyone');
    final isMentioned = !isMine && !isAnnouncement && me.isNotEmpty && body.toLowerCase().contains('@$me');
    final routeMeta = ChatRouteMeta.find(message.actionRoute, message.body);

    // Titan Terminal bubbles: mine tinted with the accent, others on the card
    // surface, mentions in accent, @everyone as a full-width gold announcement.
    final Color fill, edge;
    if (isAnnouncement) {
      (fill, edge) = (AppColors.titanGoldSoft, AppColors.titanGold);
    } else if (isMentioned) {
      (fill, edge) = (AppColors.goldPale, AppColors.goldMid);
    } else if (isMine) {
      (fill, edge) = (AppColors.goldPale, AppColors.goldBorder);
    } else {
      (fill, edge) = (AppColors.pureWhite, AppColors.birch);
    }
    const r = Radius.circular(12), tail = Radius.circular(4);

    final bubble = GestureDetector(
      onLongPress: () => _showMessageActions(message),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (isAnnouncement ? 1 : 0.76)),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: edge),
          borderRadius: isAnnouncement
              ? BorderRadius.circular(AppRadius.lg)
              : BorderRadius.only(topLeft: r, topRight: r, bottomLeft: isMine ? r : tail, bottomRight: isMine ? tail : r),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isAnnouncement || isMentioned)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isAnnouncement ? Icons.campaign_rounded : Icons.alternate_email, size: 13, color: edge),
                const SizedBox(width: 4),
                Text(isAnnouncement ? 'PRIORITY ANNOUNCEMENT' : 'MENTIONED YOU', style: AppText.badge.copyWith(color: edge)),
                if (isAnnouncement) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: AppCard.badge(AppColors.titanGold),
                    child: Text('BYPASSES MUTE', style: AppText.badge.copyWith(fontSize: 8.5, color: AppColors.parchment)),
                  ),
                ],
              ]),
            ),
          if (showAuthor || isAnnouncement)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(message.authorName ?? 'Titan',
                    style: AppFonts.sans(size: 12.5, weight: FontWeight.w600,
                        color: message.authorIsAdmin ? AppColors.goldMid : AppColors.ink2)),
                if (message.authorIsAdmin) ...[const SizedBox(width: 5), _adminTag()],
                if (message.authorTier != null && message.authorTier != 'free') ...[
                  const SizedBox(width: 4),
                  PlanBadge(tier: message.authorTier!, compact: true),
                ],
              ]),
            ),
          if (message.isImage && message.mediaPath != null) _media(message.mediaPath!, message),
          if (message.isVoice)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mic_none, size: 16, color: AppColors.ink4),
                const SizedBox(width: 4),
                Text('Voice note — update the app to play', style: AppText.bodySmall),
              ]),
            ),
          if (body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: _buildMessageText(body, isMine)),
          if (routeMeta != null) ChatRouteAttachmentCard(meta: routeMeta, isMine: isMine),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text('${message.isEdited ? 'edited · ' : ''}${_stamp(message.createdAt)}',
                style: AppFonts.sans(size: 10, color: AppColors.ink5)),
          ),
        ]),
      ),
    );

    if (isMine) return Align(alignment: Alignment.centerRight, child: bubble);
    if (isAnnouncement) return bubble;
    // Others: an initial avatar on the first message of a run, a gutter after.
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      SizedBox(
        width: 34,
        child: showAuthor
            ? Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: message.authorIsAdmin ? AppColors.imperialGold : AppColors.cream,
                  child: Text((message.authorName ?? 'T').trim().characters.firstOrNull?.toUpperCase() ?? 'T',
                      style: AppFonts.sans(size: 12, weight: FontWeight.w600,
                          color: message.authorIsAdmin ? Colors.white : AppColors.ink3)),
                ),
              )
            : null,
      ),
      Flexible(child: bubble),
    ]);
  }

  Widget _buildMessageText(String body, bool isMine) {
    final spans = <InlineSpan>[];
    final pattern =
        RegExp(r'(@everyone|@[a-zA-Z0-9_\-\.]+|/[a-zA-Z0-9\-]+)');
    int lastMatchEnd = 0;

    for (final match in pattern.allMatches(body)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: body.substring(lastMatchEnd, match.start),
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            color: AppColors.ink,
            height: 1.35,
          ),
        ));
      }

      final token = match.group(0)!;
      if (token == '@everyone') {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.imperialGold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: AppColors.imperialGold.withValues(alpha: 0.6),
                width: 0.9,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 11,
                  color: AppColors.imperialGold,
                ),
                const SizedBox(width: 2.5),
                Text(
                  '@everyone',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.imperialGold,
                  ),
                ),
              ],
            ),
          ),
        ));
      } else if (token.startsWith('@')) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.violetLight,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              token,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.violet,
              ),
            ),
          ),
        ));
      } else if (token.startsWith('/')) {
        final isKnownRoute = ChatRouteMeta.find(token) != null;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: isKnownRoute
                  ? AppColors.goldLight
                  : AppColors.birch.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isKnownRoute
                    ? AppColors.imperialGold.withValues(alpha: 0.5)
                    : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Text(
              token,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isKnownRoute ? AppColors.goldDeep : AppColors.ink2,
              ),
            ),
          ),
        ));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < body.length) {
      spans.add(TextSpan(
        text: body.substring(lastMatchEnd),
        style: GoogleFonts.ibmPlexSans(
          fontSize: 14,
          color: AppColors.ink,
          height: 1.35,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }

  /// Chat media lives in a private bucket, so each image needs a signed URL.
  Widget _media(String path, ChatMessage message) {
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
        final url = snap.data!;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GestureDetector(
            onTap: () {
              ChatImageViewer.show(
                context,
                imageUrl: url,
                caption: message.body,
                authorName: message.authorName,
                timestamp: message.createdAt,
              );
            },
            child: Hero(
              tag: 'chat_img_${message.id}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: AppNetworkImage(url: url, height: 180),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _composer() {
    if (context.watch<AuthService>().isGuest) return _guestPrompt();

    final isAdmin = context.watch<AuthService>().user?.isAdmin == true;
    final muted = _mutedUntil;
    if (muted != null) {
      return _notice(
        icon: Icons.volume_off_outlined,
        text: 'You are muted until ${_stamp(muted)} and cannot post right now.',
      );
    }

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.pureWhite,
          border: Border(top: BorderSide(color: AppColors.birch)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Editing Banner
            if (_editingMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.goldPale,
                  border: Border(bottom: BorderSide(color: AppColors.birch)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit,
                        size: 15, color: AppColors.imperialGold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Editing message',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.imperialGold,
                            ),
                          ),
                          Text(
                            _editingMessage!.body ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              color: AppColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 17, color: AppColors.ink4),
                      onPressed: _cancelEditing,
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),

            // Composer Controls
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.image_outlined, color: AppColors.ink3),
                    tooltip: 'Send a photo',
                    onPressed: _sending ? null : _sendImage,
                  ),
                  if (isAdmin) ...[
                    IconButton(
                      icon: Text(
                        '@',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.imperialGold,
                        ),
                      ),
                      tooltip: 'Tag member or @everyone',
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        final current = _controller.text;
                        _controller.text = '$current@';
                        _controller.selection = TextSelection.collapsed(
                            offset: _controller.text.length);
                        _focusNode.requestFocus();
                        _onTextChanged();
                      },
                    ),
                    IconButton(
                      icon: Text(
                        '/',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.imperialGold,
                        ),
                      ),
                      tooltip: 'Attach app screen',
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        final current = _controller.text;
                        _controller.text = '$current/';
                        _controller.selection = TextSelection.collapsed(
                            offset: _controller.text.length);
                        _focusNode.requestFocus();
                        _onTextChanged();
                      },
                    ),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _editingMessage != null
                            ? 'Edit message...'
                            : 'Message the room',
                        // Pill input, as in the design; fill and focus come from the theme.
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: AppColors.birch),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: AppColors.birch),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: AppColors.goldMid, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                        backgroundColor: AppColors.imperialGold, foregroundColor: Colors.white, fixedSize: const Size(44, 44)),
                    icon: Icon(_editingMessage != null ? Icons.check_rounded : Icons.arrow_upward_rounded),
                    tooltip: _editingMessage != null ? 'Save edit' : 'Send',
                    onPressed: _sending ? null : _sendText,
                  ),
                ],
              ),
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
                    style: GoogleFonts.ibmPlexSans(
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
              style: GoogleFonts.ibmPlexSans(
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
                    style: GoogleFonts.ibmPlexSans(
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
                  style: GoogleFonts.ibmPlexSans(
                      fontSize: 13, color: AppColors.ink3, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
