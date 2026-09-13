class VaultMember {
  const VaultMember({
    required this.id,
    required this.email,
    this.name,
    required this.role,
  });
  final String id;
  final String email;
  final String? name;
  final String role;
  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get canWrite => role != 'viewer';

  factory VaultMember.fromJson(Map<String, dynamic> json) => VaultMember(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['full_name'] as String?,
    role: json['role'] as String,
  );
}

class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.name,
    required this.scope,
    required this.category,
    required this.storagePath,
    required this.sizeBytes,
    required this.createdAt,
    this.mimeType,
    this.ownerId,
    this.expiresAt,
    this.isFavorite = false,
    this.tags = const [],
    this.compressed = false,
  });
  final String id, name, scope, category, storagePath;
  final String? mimeType, ownerId;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isFavorite;
  final List<String> tags;
  final bool compressed;

  factory VaultDocument.fromJson(Map<String, dynamic> j) => VaultDocument(
    id: j['id'],
    name: j['name'],
    scope: j['scope'],
    category: j['category'],
    storagePath: j['storage_path'],
    mimeType: j['mime_type'],
    ownerId: j['owner_id'],
    sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(j['created_at']),
    expiresAt: j['expires_at'] == null ? null : DateTime.parse(j['expires_at']),
    isFavorite: j['is_favorite'] ?? false,
    tags: List<String>.from(j['tags'] ?? const []),
    compressed: j['compressed'] ?? false,
  );
}

class VaultNote {
  const VaultNote({
    required this.id,
    required this.title,
    required this.body,
    required this.scope,
    required this.category,
    required this.createdAt,
    required this.createdBy,
    this.ownerId,
    this.isPinned = false,
    this.tags = const [],
  });
  final String id, title, body, scope, category, createdBy;
  final String? ownerId;
  final DateTime createdAt;
  final bool isPinned;
  final List<String> tags;

  factory VaultNote.fromJson(Map<String, dynamic> j) => VaultNote(
    id: j['id'],
    title: j['title'],
    body: j['body'] ?? '',
    scope: j['scope'],
    category: j['category'] ?? 'General',
    createdBy: j['created_by'],
    ownerId: j['owner_id'],
    createdAt: DateTime.parse(j['created_at']),
    isPinned: j['is_pinned'] ?? false,
    tags: List<String>.from(j['tags'] ?? const []),
  );
}

class VaultTodo {
  const VaultTodo({
    required this.id,
    required this.title,
    required this.assignedTo,
    required this.priority,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.details,
    this.dueDate,
  });
  final String id, title, assignedTo, priority, status, createdBy;
  final String? details;
  final DateTime createdAt;
  final DateTime? dueDate;

  bool get isDone => status == 'done';
  bool get isOverdue =>
      !isDone &&
      dueDate != null &&
      dueDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)));

  factory VaultTodo.fromJson(Map<String, dynamic> j) => VaultTodo(
    id: j['id'],
    title: j['title'],
    assignedTo: j['assigned_to'],
    priority: j['priority'] ?? 'Normal',
    status: j['status'] ?? 'open',
    createdBy: j['created_by'],
    details: j['details'],
    createdAt: DateTime.parse(j['created_at']),
    dueDate: j['due_date'] == null ? null : DateTime.parse(j['due_date']),
  );
}

class VaultNotification {
  const VaultNotification({
    required this.id,
    required this.title,
    required this.kind,
    required this.isRead,
    required this.createdAt,
    this.body,
  });
  final String id, title, kind;
  final String? body;
  final bool isRead;
  final DateTime createdAt;

  factory VaultNotification.fromJson(Map<String, dynamic> j) =>
      VaultNotification(
        id: j['id'],
        title: j['title'],
        body: j['body'],
        kind: j['kind'] ?? 'general',
        isRead: j['is_read'] ?? false,
        createdAt: DateTime.parse(j['created_at']),
      );
}

class PasswordEntry {
  const PasswordEntry({
    required this.id,
    required this.title,
    required this.secret,
    required this.scope,
    this.website,
    this.username,
    this.email,
    this.url,
    this.notes,
    this.ownerId,
    this.isFavorite = false,
  });
  final String id, title, secret, scope;
  final String? website, username, email, url, notes, ownerId;
  final bool isFavorite;

  factory PasswordEntry.fromJson(Map<String, dynamic> j) => PasswordEntry(
    id: j['id'],
    title: j['title'],
    secret: j['secret'],
    scope: j['scope'],
    website: j['website'],
    username: j['username'],
    email: j['email'],
    url: j['url'],
    notes: j['notes'],
    ownerId: j['owner_id'],
    isFavorite: j['is_favorite'] ?? false,
  );
}

class SharedLink {
  const SharedLink({
    required this.id,
    required this.url,
    required this.category,
    required this.createdAt,
    this.title,
    this.description,
    this.isFavorite = false,
    this.theme = 'Other',
  });
  final String id, url, category;
  final String? title, description;
  final DateTime createdAt;
  final bool isFavorite;
  final String theme;
  factory SharedLink.fromJson(Map<String, dynamic> j) => SharedLink(
    id: j['id'],
    url: j['url'],
    category: j['category'],
    title: j['title'],
    description: j['description'],
    createdAt: DateTime.parse(j['created_at']),
    isFavorite: j['is_favorite'] ?? false,
    theme: j['theme'] ?? 'Other',
  );
}

class VaultImage {
  const VaultImage({
    required this.id,
    required this.name,
    required this.album,
    required this.storagePath,
    required this.createdAt,
    this.isFavorite = false,
  });
  final String id, name, album, storagePath;
  final DateTime createdAt;
  final bool isFavorite;
  factory VaultImage.fromJson(Map<String, dynamic> j) => VaultImage(
    id: j['id'],
    name: j['name'],
    album: j['album'],
    storagePath: j['storage_path'],
    createdAt: DateTime.parse(j['created_at']),
    isFavorite: j['is_favorite'] ?? false,
  );
}

class ActivityItem {
  const ActivityItem({
    required this.action,
    required this.createdAt,
    this.entityName,
  });
  final String action;
  final String? entityName;
  final DateTime createdAt;
  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
    action: j['action'],
    entityName: j['entity_name'],
    createdAt: DateTime.parse(j['created_at']),
  );
}
