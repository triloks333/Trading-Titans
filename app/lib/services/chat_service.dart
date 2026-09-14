import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One message in the public room.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.kind,
    required this.createdAt,
    this.body,
    this.mediaPath,
    this.durationMs,
    this.authorName,
    this.authorTier,
    this.authorIsAdmin = false,
  });

  final String id;
  final String userId;

  /// 'text' | 'image' | 'voice'. Kept as a string rather than an enum because the
  /// server's CHECK constraint is the authority, and an unknown kind arriving from
  /// a newer client should render as unsupported rather than crash a parse.
  final String kind;
  final DateTime createdAt;
  final String? body;
  final String? mediaPath;
  final int? durationMs;
  final String? authorName;
  final String? authorTier;

  /// Wears the moderator tag in the room. Comes from `profiles.is_admin`, which is
  /// already true for exactly the three intended accounts, rather than a fourth
  /// hardcoded copy of the owner email list.
  final bool authorIsAdmin;

  /// Reads a row from `public.chat_feed`, which already carries the author's name
  /// and tier as flat columns.
  static ChatMessage fromRow(Map<String, dynamic> row) {
    return ChatMessage(
      id: '${row['id']}',
      userId: '${row['user_id']}',
      kind: '${row['kind'] ?? 'text'}',
      createdAt:
          DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
      body: row['body'] as String?,
      mediaPath: row['media_path'] as String?,
      durationMs: row['duration_ms'] is num
          ? (row['duration_ms'] as num).toInt()
          : null,
      authorName: row['author_name'] as String?,
      authorTier: row['author_tier'] as String?,
      authorIsAdmin: row['author_is_admin'] == true,
    );
  }

  bool get isImage => kind == 'image';
  bool get isVoice => kind == 'voice';
}

/// Reads and writes the single public chat room.
///
/// Thin on purpose. Every rule that matters — links are admin only, guests cannot
/// post, mutes, the rate limit — is enforced by the `chat_before_insert` trigger in
/// the database, so this class does not re-implement any of it. It surfaces the
/// server's message instead, which means a rule added server-side starts being
/// explained to users without an app release.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const String bucket = 'chat-media';

  /// One page of history. The room is read oldest-last for display, so this
  /// fetches newest-first and reverses.
  static const int pageSize = 50;

  SupabaseClient get _db => Supabase.instance.client;

  /// Reads go through `public.chat_feed`, not `chat_messages`.
  ///
  /// Not a preference. `chat_messages.user_id` references `auth.users`, so
  /// PostgREST cannot embed `profiles` — there is no relationship to follow — and
  /// `profiles` is own-row-only under RLS anyway, so a join would have returned a
  /// blank author on every message except your own. The view resolves both, and it
  /// already filters soft-deleted rows.
  static const String _columns =
      'id, user_id, kind, body, media_path, duration_ms, created_at, '
      'author_name, author_tier, author_is_admin';

  static const String _view = 'chat_feed';

  Future<List<ChatMessage>> loadRecent({DateTime? before}) async {
    try {
      var query = _db.from(_view).select(_columns);
      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(pageSize);
      final list = (rows as List)
          .map((r) => ChatMessage.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
      // Oldest first, which is the order the list renders in.
      return list.reversed.toList();
    } catch (e) {
      debugPrint('ChatService.loadRecent failed: $e');
      return const [];
    }
  }

  /// Fetches one message with its author, for a realtime insert that arrived
  /// without the join.
  Future<ChatMessage?> fetchOne(String id) async {
    try {
      final row =
          await _db.from(_view).select(_columns).eq('id', id).maybeSingle();
      if (row == null) return null;
      return ChatMessage.fromRow(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      debugPrint('ChatService.fetchOne failed: $e');
      return null;
    }
  }

  /// Subscribes to new messages. Returns the channel so the caller can dispose it.
  ///
  /// Only INSERT is watched. Deletes are soft, and a soft delete arrives as an
  /// UPDATE that RLS then hides — so rather than reconcile that live, a removed
  /// message disappears on the next open. Moderation is not a real-time need and
  /// pretending otherwise would mean re-fetching the room on every edit.
  RealtimeChannel subscribe(void Function(String messageId) onInsert) {
    final channel = _db.channel('public:chat_messages');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_messages',
      callback: (payload) {
        final id = payload.newRecord['id'];
        if (id != null) onInsert('$id');
      },
    ).subscribe();
    return channel;
  }

  /// Posts a text message. Returns null on success, or the reason it was refused.
  ///
  /// The reason is the server's own, minus the 'chat: ' prefix the trigger uses to
  /// mark its messages as safe to show a user. Anything without that prefix is an
  /// unexpected failure and gets generic copy, so a raw Postgres error can never
  /// reach the UI.
  Future<String?> sendText(String body) async {
    final text = body.trim();
    if (text.isEmpty) return 'Type something first.';
    return _insert({'kind': 'text', 'body': text});
  }

  /// Posts an image, with an optional caption. [bytes] should already be
  /// compressed by the caller.
  Future<String?> sendImage({
    required Uint8List bytes,
    required String extension,
    String? caption,
  }) async {
    final path = await _upload(bytes, extension, contentTypeFor(extension));
    if (path == null) return 'That image could not be uploaded.';
    final text = caption?.trim();
    return _insert({
      'kind': 'image',
      'media_path': path,
      'body': (text == null || text.isEmpty) ? null : text,
    });
  }

  /// Posts a voice note. [durationMs] must be 60000 or less; the server rejects
  /// more, and this exists so the user is told before the upload rather than after.
  Future<String?> sendVoice({
    required Uint8List bytes,
    required String extension,
    required int durationMs,
  }) async {
    if (durationMs <= 0) return 'That recording was empty.';
    if (durationMs > 60000) return 'Voice notes are capped at 60 seconds.';
    final path = await _upload(bytes, extension, contentTypeFor(extension));
    if (path == null) return 'That recording could not be uploaded.';
    return _insert({
      'kind': 'voice',
      'media_path': path,
      'duration_ms': durationMs,
    });
  }

  Future<String?> _insert(Map<String, dynamic> row) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 'Sign in to post.';
    try {
      await _db.from('chat_messages').insert({...row, 'user_id': uid});
      return null;
    } catch (e) {
      return readableFailure(e);
    }
  }

  /// Uploads to the caller's own folder, which is what the storage policy allows.
  Future<String?> _upload(
      Uint8List bytes, String extension, String contentType) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    // The uid prefix is required by the bucket policy; the timestamp keeps two
    // uploads in the same second apart.
    final path =
        '$uid/${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.$extension';
    try {
      await _db.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      return path;
    } catch (e) {
      debugPrint('ChatService._upload failed: $e');
      return null;
    }
  }

  /// A signed URL for private chat media. The bucket is deliberately not public,
  /// so a link copied out of the app stops working.
  Future<String?> mediaUrl(String path) async {
    try {
      return await _db.storage.from(bucket).createSignedUrl(path, 60 * 60);
    } catch (e) {
      debugPrint('ChatService.mediaUrl failed: $e');
      return null;
    }
  }

  Future<bool> report(String messageId, {String? reason}) async {
    try {
      await _db.rpc('report_chat_message',
          params: {'p_message_id': messageId, 'p_reason': reason});
      return true;
    } catch (e) {
      debugPrint('ChatService.report failed: $e');
      return false;
    }
  }

  /// Admin only, enforced inside the RPC.
  Future<bool> deleteMessage(String messageId) async {
    try {
      await _db.rpc('delete_chat_message', params: {'p_message_id': messageId});
      return true;
    } catch (e) {
      debugPrint('ChatService.deleteMessage failed: $e');
      return false;
    }
  }

  /// Admin only. Returns the moment the mute lifts, or null if it failed.
  Future<DateTime?> muteUser(String userId, {int days = 1, String? reason}) async {
    try {
      final result = await _db.rpc('mute_chat_user',
          params: {'p_user_id': userId, 'p_days': days, 'p_reason': reason});
      return DateTime.tryParse('$result')?.toLocal();
    } catch (e) {
      debugPrint('ChatService.muteUser failed: $e');
      return null;
    }
  }

  /// When the signed-in user's own mute lifts, or null when they are not muted.
  /// Lets the composer explain itself instead of failing on send.
  Future<DateTime?> myMutedUntil() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _db
          .from('chat_mutes')
          .select('muted_until')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return null;
      final until = DateTime.tryParse('${(row as Map)['muted_until']}')?.toLocal();
      if (until == null || until.isBefore(DateTime.now())) return null;
      return until;
    } catch (e) {
      debugPrint('ChatService.myMutedUntil failed: $e');
      return null;
    }
  }

  static String contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'mp3':
        return 'audio/mpeg';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'image/jpeg';
    }
  }

  /// Turns a thrown Postgres error into something worth showing a user.
  ///
  /// The trigger prefixes every message it raises with 'chat: ', which is the
  /// signal that the text was written for a human. Everything else — a constraint
  /// name, a permission error, a network failure — gets generic copy, so an
  /// internal detail cannot leak into the room UI.
  @visibleForTesting
  static String readableFailure(Object error) {
    final raw = error is PostgrestException ? error.message : error.toString();
    final marker = raw.indexOf('chat: ');
    if (marker != -1) {
      final message = raw.substring(marker + 'chat: '.length).trim();
      if (message.isNotEmpty) {
        // Capitalise, since it is going straight into a snackbar.
        return message[0].toUpperCase() + message.substring(1);
      }
    }
    if (error is SocketException) {
      return 'You appear to be offline.';
    }
    return 'That message could not be sent. Please try again.';
  }
}
