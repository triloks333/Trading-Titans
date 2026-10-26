// The public chat room's client-side trust boundary.
//
// Every posting rule is enforced by the `chat_before_insert` trigger, so the client
// has exactly one job when a send fails: decide whether the server's text is safe to
// show a user. The trigger prefixes everything it raises with 'chat: ' precisely so
// that decision can be made on a marker rather than on guesswork.
//
// Getting it wrong in either direction is bad: too permissive and a raw Postgres
// error (constraint names, table names, a permission failure) lands in the room UI;
// too strict and a user who broke a rule is told nothing useful and retries forever.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/chat_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException _pg(String message) =>
    PostgrestException(message: message, code: '23514');

void main() {
  group('readableFailure', () {
    test('the server rules reach the user in their own words', () {
      // These are the exact strings the trigger raises.
      expect(
        ChatService.readableFailure(_pg('chat: links can only be posted by admins')),
        'Links can only be posted by admins',
      );
      expect(
        ChatService.readableFailure(
            _pg('chat: create a free account to post in the room')),
        'Create a free account to post in the room',
      );
      expect(
        ChatService.readableFailure(
            _pg('chat: you are posting too quickly, wait a moment')),
        'You are posting too quickly, wait a moment',
      );
      expect(
        ChatService.readableFailure(_pg('chat: you can only post as yourself')),
        'You can only post as yourself',
      );
    });

    test('the marker is found even when Postgres wraps the message', () {
      // A real PostgrestException often carries context around the raised text.
      expect(
        ChatService.readableFailure(_pg(
            'new row violates ... ERROR: chat: you are muted until 2026-09-15 10:00:00+00')),
        startsWith('You are muted until'),
      );
    });

    test('anything without the marker gets generic copy', () {
      // THE POINT OF THE FUNCTION. None of these should ever be shown verbatim.
      for (final leak in [
        'duplicate key value violates unique constraint "chat_reports_message_id_reporter_id_key"',
        'new row violates row-level security policy for table "chat_messages"',
        'permission denied for table chat_messages',
        'relation "public.chat_messages" does not exist',
        'JWT expired',
        '',
      ]) {
        final shown = ChatService.readableFailure(_pg(leak));
        expect(shown, 'That message could not be sent. Please try again.',
            reason: 'must not surface: $leak');
      }
    });

    test('a non-Postgres error is also handled', () {
      expect(
        ChatService.readableFailure(Exception('something odd')),
        'That message could not be sent. Please try again.',
      );
    });

    test('an empty message after the marker does not produce empty copy', () {
      // Otherwise the snackbar would render blank, which reads as a silent failure.
      expect(
        ChatService.readableFailure(_pg('chat: ')),
        'That message could not be sent. Please try again.',
      );
    });
  });

  group('ChatMessage.fromRow', () {
    test('reads a chat_feed row', () {
      final m = ChatMessage.fromRow({
        'id': 'abc',
        'user_id': 'user-1',
        'kind': 'text',
        'body': 'hello',
        'media_path': null,
        'duration_ms': null,
        'created_at': '2026-09-14T10:00:00Z',
        'author_name': 'Manav',
        'author_tier': 'titan',
      });
      expect(m.id, 'abc');
      expect(m.body, 'hello');
      expect(m.authorName, 'Manav');
      expect(m.authorTier, 'titan');
      expect(m.isImage, isFalse);
      expect(m.isVoice, isFalse);
    });

    test('the admin tag is read from the feed', () {
      expect(
        ChatMessage.fromRow({
          'id': 'a', 'user_id': 'u', 'kind': 'text', 'body': 'hi',
          'created_at': '2026-09-14T10:00:00Z',
          'author_name': 'Pawan', 'author_is_admin': true,
        }).authorIsAdmin,
        isTrue,
      );
    });

    test('a missing admin flag is not an admin', () {
      // An older row, or a payload from a build that did not select the column,
      // must never be mistaken for a moderator — that badge is what tells users a
      // link or an announcement is genuine.
      for (final value in [null, false, 'false', 0, '']) {
        expect(
          ChatMessage.fromRow({
            'id': 'a', 'user_id': 'u', 'kind': 'text', 'body': 'hi',
            'created_at': '2026-09-14T10:00:00Z',
            'author_is_admin': value,
          }).authorIsAdmin,
          isFalse,
          reason: 'author_is_admin=$value was treated as admin',
        );
      }
      // Absent entirely.
      expect(
        ChatMessage.fromRow({
          'id': 'a', 'user_id': 'u', 'kind': 'text', 'body': 'hi',
          'created_at': '2026-09-14T10:00:00Z',
        }).authorIsAdmin,
        isFalse,
      );
    });

    test('an unknown kind does not throw', () {
      // kind is a string, not an enum, so a message from a newer build renders as
      // unsupported instead of crashing the whole room.
      final m = ChatMessage.fromRow({
        'id': 'x',
        'user_id': 'u',
        'kind': 'hologram',
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(m.kind, 'hologram');
      expect(m.isImage, isFalse);
      expect(m.isVoice, isFalse);
    });

    test('a missing or unparseable timestamp still yields a message', () {
      // A row that cannot be placed in time is still better shown than dropped.
      final m = ChatMessage.fromRow({
        'id': 'x',
        'user_id': 'u',
        'kind': 'text',
        'body': 'hi',
        'created_at': 'not a date',
      });
      expect(m.body, 'hi');
      expect(m.createdAt, isNotNull);
    });

    test('voice carries its duration', () {
      final m = ChatMessage.fromRow({
        'id': 'v',
        'user_id': 'u',
        'kind': 'voice',
        'media_path': 'u/1.m4a',
        'duration_ms': 12000,
        'created_at': '2026-09-14T10:00:00Z',
      });
      expect(m.isVoice, isTrue);
      expect(m.durationMs, 12000);
    });

    test('edited_at is read from the feed', () {
      final m = ChatMessage.fromRow({
        'id': 'abc',
        'user_id': 'u',
        'kind': 'text',
        'body': 'updated text',
        'created_at': '2026-09-14T10:00:00Z',
        'edited_at': '2026-09-14T10:05:00Z',
      });
      expect(m.isEdited, isTrue);
      expect(m.editedAt, isNotNull);
    });

    test('null edited_at leaves isEdited false', () {
      final m = ChatMessage.fromRow({
        'id': 'abc',
        'user_id': 'u',
        'kind': 'text',
        'body': 'regular text',
        'created_at': '2026-09-14T10:00:00Z',
        'edited_at': null,
      });
      expect(m.isEdited, isFalse);
      expect(m.editedAt, isNull);
    });
  });

  group('contentTypeFor', () {
    test('every type maps to something the bucket allows', () {
      // The bucket's allowed_mime_types is the gate; a type outside it fails the
      // upload with a storage error rather than anything readable.
      const allowed = {
        'image/jpeg', 'image/png', 'image/webp',
        'audio/aac', 'audio/mp4', 'audio/m4a',
        'audio/mpeg', 'audio/ogg', 'audio/webm',
      };
      for (final ext in ['jpg', 'jpeg', 'png', 'webp', 'm4a', 'mp4', 'aac', 'mp3', 'ogg']) {
        expect(allowed, contains(ChatService.contentTypeFor(ext)),
            reason: '$ext maps outside the bucket allow-list');
      }
    });

    test('an unknown extension falls back to jpeg rather than failing', () {
      expect(ChatService.contentTypeFor('heic'), 'image/jpeg');
      expect(ChatService.contentTypeFor(''), 'image/jpeg');
    });
  });
}
