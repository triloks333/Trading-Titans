import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/compression.dart';
import '../core/config.dart';
import 'vault_models.dart';

class VaultRepository {
  VaultRepository(this.client);
  final SupabaseClient client;

  User get user => client.auth.currentUser!;

  Future<VaultMember> ensureMember() async {
    final found = await client
        .from('kv_members')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    if (found != null) return VaultMember.fromJson(found);
    final data = await client
        .from('kv_members')
        .insert({
          'id': user.id,
          'email': user.email ?? '',
          'full_name':
              user.userMetadata?['full_name'] ?? user.userMetadata?['name'],
          'last_login_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();
    await activity('signed in', type: 'member', id: user.id, name: user.email);
    return VaultMember.fromJson(data);
  }

  Future<List<VaultMember>> members() async =>
      (await client.from('kv_members').select().order('created_at'))
          .map<VaultMember>((e) => VaultMember.fromJson(e))
          .toList();

  Future<void> setRole(String id, String role) async {
    await client.from('kv_members').update({'role': role}).eq('id', id);
    await activity('changed role to $role', type: 'member', id: id);
  }

  Stream<List<VaultDocument>> watchDocuments(String scope) => client
      .from('kv_documents')
      .stream(primaryKey: ['id'])
      .eq('scope', scope)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(VaultDocument.fromJson).toList());

  String _path(String scope, String id, String name, {String? ownerId}) =>
      scope == 'company'
      ? 'company/$id/$name'
      : 'personal/${ownerId ?? user.id}/$id/$name';

  String _mime(String name) {
    final ext = name.split('.').last.toLowerCase();
    return const {
          'pdf': 'application/pdf',
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'doc': 'application/msword',
          'docx':
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          'xls': 'application/vnd.ms-excel',
          'xlsx':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'zip': 'application/zip',
          'mp4': 'video/mp4',
        }[ext] ??
        'application/octet-stream';
  }

  Future<void> uploadDocument({
    required PlatformFile file,
    required String scope,
    required String category,
    String? ownerId,
    DateTime? expiresAt,
    List<String> tags = const [],
  }) async {
    if (file.path == null) {
      throw const FileSystemException('The selected file is unavailable');
    }
    final id = _uuid();
    final personalOwnerId = scope == 'personal' ? (ownerId ?? user.id) : null;
    final raw = await File(file.path!).readAsBytes();
    final packed = packForUpload(raw);
    final path =
        '${_path(scope, id, file.name, ownerId: personalOwnerId)}${packed.compressed ? '.gz' : ''}';
    await client.storage
        .from(bucketDocuments)
        .uploadBinary(
          path,
          packed.bytes,
          fileOptions: FileOptions(
            contentType: packed.compressed
                ? 'application/gzip'
                : _mime(file.name),
          ),
        );
    try {
      await client.from('kv_documents').insert({
        'id': id,
        'name': file.name,
        'scope': scope,
        'category': category,
        'owner_id': personalOwnerId,
        'storage_path': path,
        'mime_type': _mime(file.name),
        'size_bytes': packed.bytes.length,
        'compressed': packed.compressed,
        'tags': tags,
        'expires_at': expiresAt?.toIso8601String().split('T').first,
        'created_by': user.id,
      });
      await activity(
        'uploaded',
        type: 'document',
        id: id,
        name: file.name,
        scope: scope,
        ownerId: personalOwnerId,
      );
    } catch (_) {
      await client.storage.from(bucketDocuments).remove([path]);
      rethrow;
    }
  }

  Future<void> openObject(
    String bucket,
    String path,
    String fileName, {
    bool compressed = false,
  }) async {
    final stored = await client.storage.from(bucket).download(path);
    final bytes = unpackDownload(stored, compressed: compressed);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFilex.open(file.path);
  }

  Future<String> signedUrl(String bucket, String path) =>
      client.storage.from(bucket).createSignedUrl(path, signedUrlSeconds);

  Future<void> toggleDocument(VaultDocument document) => client
      .from('kv_documents')
      .update({'is_favorite': !document.isFavorite})
      .eq('id', document.id);

  Future<void> deleteDocument(VaultDocument document) async {
    await client.storage.from(bucketDocuments).remove([document.storagePath]);
    await client.from('kv_documents').delete().eq('id', document.id);
    await activity(
      'deleted',
      type: 'document',
      id: document.id,
      name: document.name,
      scope: document.scope,
      ownerId: document.ownerId,
    );
  }

  Future<List<PasswordEntry>> passwords() async =>
      (await client
              .from('kv_passwords')
              .select()
              .order('updated_at', ascending: false))
          .map<PasswordEntry>((e) => PasswordEntry.fromJson(e))
          .toList();

  Future<void> savePassword({
    String? id,
    required Map<String, dynamic> values,
  }) async {
    final data = <String, dynamic>{...values, 'created_by': user.id};
    if (values['scope'] == 'personal') data['owner_id'] = user.id;
    if (id == null) {
      final row = await client
          .from('kv_passwords')
          .insert(data)
          .select('id,title')
          .single();
      await activity(
        'created',
        type: 'password',
        id: row['id'],
        name: row['title'],
        scope: values['scope'],
        ownerId: values['scope'] == 'personal' ? user.id : null,
      );
    } else {
      data.remove('created_by');
      await client
          .from('kv_passwords')
          .update({
            ...data,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
      await activity(
        'updated',
        type: 'password',
        id: id,
        name: values['title'],
        scope: values['scope'],
        ownerId: values['scope'] == 'personal' ? user.id : null,
      );
    }
  }

  Future<void> deletePassword(PasswordEntry entry) async {
    await client.from('kv_passwords').delete().eq('id', entry.id);
    await activity(
      'deleted',
      type: 'password',
      id: entry.id,
      name: entry.title,
      scope: entry.scope,
      ownerId: entry.ownerId,
    );
  }

  Future<List<SharedLink>> links() async =>
      (await client
              .from('kv_links')
              .select()
              .order('created_at', ascending: false))
          .map<SharedLink>((e) => SharedLink.fromJson(e))
          .toList();

  Future<void> addLink(Map<String, dynamic> values) async {
    final row = await client
        .from('kv_links')
        .insert({...values, 'shared_by': user.id})
        .select('id,title')
        .single();
    await activity('shared', type: 'link', id: row['id'], name: row['title']);
  }

  Future<void> deleteLink(SharedLink link) async {
    await client.from('kv_links').delete().eq('id', link.id);
    await activity('deleted', type: 'link', id: link.id, name: link.title);
  }

  Future<List<VaultImage>> images() async =>
      (await client
              .from('kv_images')
              .select()
              .order('created_at', ascending: false))
          .map<VaultImage>((e) => VaultImage.fromJson(e))
          .toList();

  Future<void> uploadImage(PlatformFile file, String album) async {
    if (file.path == null) {
      throw const FileSystemException('The selected image is unavailable');
    }
    final id = _uuid();
    final path = 'company/$id/${file.name}';
    await client.storage
        .from(bucketImages)
        .upload(
          path,
          File(file.path!),
          fileOptions: FileOptions(contentType: _mime(file.name)),
        );
    try {
      await client.from('kv_images').insert({
        'id': id,
        'name': file.name,
        'album': album,
        'storage_path': path,
        'size_bytes': file.size,
        'uploaded_by': user.id,
      });
      await activity('uploaded', type: 'image', id: id, name: file.name);
    } catch (_) {
      await client.storage.from(bucketImages).remove([path]);
      rethrow;
    }
  }

  Future<void> deleteImage(VaultImage image) async {
    await client.storage.from(bucketImages).remove([image.storagePath]);
    await client.from('kv_images').delete().eq('id', image.id);
    await activity('deleted', type: 'image', id: image.id, name: image.name);
  }

  Future<List<Map<String, dynamic>>> signatures() async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('kv_signatures')
            .select()
            .order('created_at', ascending: false),
      );

  Future<void> uploadSignature(
    PlatformFile file,
    String name,
    String scope,
  ) async {
    if (file.path == null) {
      throw const FileSystemException('The selected signature is unavailable');
    }
    final id = _uuid();
    final path = _path(scope, id, file.name);
    await client.storage
        .from(bucketSignatures)
        .upload(
          path,
          File(file.path!),
          fileOptions: FileOptions(contentType: _mime(file.name)),
        );
    try {
      await client.from('kv_signatures').insert({
        'id': id,
        'name': name,
        'scope': scope,
        'owner_id': scope == 'personal' ? user.id : null,
        'storage_path': path,
        'created_by': user.id,
      });
      await activity(
        'uploaded',
        type: 'signature',
        id: id,
        name: name,
        scope: scope,
        ownerId: scope == 'personal' ? user.id : null,
      );
    } catch (_) {
      await client.storage.from(bucketSignatures).remove([path]);
      rethrow;
    }
  }

  Future<List<ActivityItem>> activityFeed({int limit = 15}) async =>
      (await client
              .from('kv_activity')
              .select()
              .order('created_at', ascending: false)
              .limit(limit))
          .map<ActivityItem>((e) => ActivityItem.fromJson(e))
          .toList();

  Future<void> activity(
    String action, {
    String? type,
    String? id,
    String? name,
    String scope = 'company',
    String? ownerId,
  }) => client.from('kv_activity').insert({
    'actor_id': user.id,
    'action': action,
    'entity_type': type,
    'entity_id': id,
    'entity_name': name,
    'scope': scope,
    'owner_id': scope == 'personal' ? (ownerId ?? user.id) : null,
  });

  // ------------------------------------------------------------- notes ---
  Stream<List<VaultNote>> watchNotes() => client
      .from('kv_notes')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(VaultNote.fromJson).toList());

  Future<void> saveNote({
    String? id,
    required String title,
    required String body,
    required String scope,
    required String category,
    List<String> tags = const [],
  }) async {
    final data = {
      'title': title,
      'body': body,
      'scope': scope,
      'category': category,
      'tags': tags,
      'owner_id': scope == 'personal' ? user.id : null,
    };
    if (id == null) {
      final row = await client
          .from('kv_notes')
          .insert({...data, 'created_by': user.id})
          .select('id')
          .single();
      await activity(
        'posted',
        type: 'note',
        id: row['id'],
        name: title,
        scope: scope,
      );
    } else {
      await client
          .from('kv_notes')
          .update({
            ...data,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
      await activity(
        'updated',
        type: 'note',
        id: id,
        name: title,
        scope: scope,
      );
    }
  }

  Future<void> pinNote(VaultNote note) => client
      .from('kv_notes')
      .update({'is_pinned': !note.isPinned})
      .eq('id', note.id);

  Future<void> deleteNote(VaultNote note) async {
    await client.from('kv_notes').delete().eq('id', note.id);
    await activity(
      'deleted',
      type: 'note',
      id: note.id,
      name: note.title,
      scope: note.scope,
    );
  }

  // ------------------------------------------------------------- todos ---
  Stream<List<VaultTodo>> watchTodos() => client
      .from('kv_todos')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(VaultTodo.fromJson).toList());

  Future<void> saveTodo({
    String? id,
    required String title,
    String? details,
    required String assignedTo,
    required String priority,
    DateTime? dueDate,
  }) async {
    final data = {
      'title': title,
      'details': details,
      'assigned_to': assignedTo,
      'priority': priority,
      'due_date': dueDate?.toIso8601String().split('T').first,
    };
    if (id == null) {
      final row = await client
          .from('kv_todos')
          .insert({...data, 'created_by': user.id})
          .select('id')
          .single();
      await activity('created task', type: 'todo', id: row['id'], name: title);
    } else {
      await client
          .from('kv_todos')
          .update({
            ...data,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
      await activity('updated task', type: 'todo', id: id, name: title);
    }
  }

  Future<void> setTodoStatus(VaultTodo todo, String status) async {
    await client
        .from('kv_todos')
        .update({
          'status': status,
          'completed_at': status == 'done'
              ? DateTime.now().toUtc().toIso8601String()
              : null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', todo.id);
    await activity(
      status == 'done' ? 'completed task' : 'reopened task',
      type: 'todo',
      id: todo.id,
      name: todo.title,
    );
  }

  Future<void> deleteTodo(VaultTodo todo) async {
    await client.from('kv_todos').delete().eq('id', todo.id);
    await activity('deleted task', type: 'todo', id: todo.id, name: todo.title);
  }

  // ----------------------------------------------------- notifications ---
  Stream<List<VaultNotification>> watchNotifications() => client
      .from('kv_notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)
      .order('created_at', ascending: false)
      .limit(60)
      .map((rows) => rows.map(VaultNotification.fromJson).toList());

  Future<void> markNotificationsRead() => client
      .from('kv_notifications')
      .update({'is_read': true})
      .eq('user_id', user.id)
      .eq('is_read', false);

  Future<void> signOut() => client.auth.signOut();

  String generatePassword({int length = 20}) {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%^&*_-+=';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  Future<List<Map<String, dynamic>>> invites() async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('kv_invites')
            .select()
            .order('created_at', ascending: false),
      );

  Future<void> invite(String email, String role) async {
    await client.from('kv_invites').insert({
      'email': email.trim().toLowerCase(),
      'role': role,
      'invited_by': user.id,
    });
    await activity(
      'invited as $role',
      type: 'member',
      name: email.trim().toLowerCase(),
    );
  }

  Future<void> deleteInvite(String id) =>
      client.from('kv_invites').delete().eq('id', id);

  String _uuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
