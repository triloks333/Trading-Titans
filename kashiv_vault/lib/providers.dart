import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/push_service.dart';
import 'data/vault_models.dart';
import 'data/vault_repository.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
final repositoryProvider = Provider<VaultRepository>(
  (ref) => VaultRepository(ref.watch(supabaseProvider)),
);

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.watch(supabaseProvider)),
);

final authProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final memberProvider = FutureProvider.autoDispose<VaultMember>((ref) {
  ref.watch(authProvider);
  return ref.watch(repositoryProvider).ensureMember();
});

final documentsProvider = StreamProvider.autoDispose
    .family<List<VaultDocument>, String>((ref, scope) async* {
      await ref.watch(memberProvider.future);
      yield* ref.watch(repositoryProvider).watchDocuments(scope);
    });

final passwordsProvider = FutureProvider.autoDispose<List<PasswordEntry>>((
  ref,
) async {
  await ref.watch(memberProvider.future);
  return ref.watch(repositoryProvider).passwords();
});

final linksProvider = FutureProvider.autoDispose<List<SharedLink>>((ref) async {
  await ref.watch(memberProvider.future);
  return ref.watch(repositoryProvider).links();
});

final imagesProvider = FutureProvider.autoDispose<List<VaultImage>>((
  ref,
) async {
  await ref.watch(memberProvider.future);
  return ref.watch(repositoryProvider).images();
});

final signaturesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      await ref.watch(memberProvider.future);
      return ref.watch(repositoryProvider).signatures();
    });

final membersProvider = FutureProvider.autoDispose<List<VaultMember>>((
  ref,
) async {
  await ref.watch(memberProvider.future);
  return ref.watch(repositoryProvider).members();
});

final invitesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  await ref.watch(memberProvider.future);
  return ref.watch(repositoryProvider).invites();
});

final activityProvider = FutureProvider.autoDispose<List<ActivityItem>>((
  ref,
) async {
  await ref.watch(memberProvider.future);
  return ref.watch(repositoryProvider).activityFeed();
});

final notesProvider = StreamProvider.autoDispose<List<VaultNote>>((ref) async* {
  await ref.watch(memberProvider.future);
  yield* ref.watch(repositoryProvider).watchNotes();
});

final todosProvider = StreamProvider.autoDispose<List<VaultTodo>>((ref) async* {
  await ref.watch(memberProvider.future);
  yield* ref.watch(repositoryProvider).watchTodos();
});

final notificationsProvider =
    StreamProvider.autoDispose<List<VaultNotification>>((ref) async* {
      await ref.watch(memberProvider.future);
      yield* ref.watch(repositoryProvider).watchNotifications();
    });

final unreadCountProvider = Provider.autoDispose<int>(
  (ref) =>
      ref
          .watch(notificationsProvider)
          .value
          ?.where((item) => !item.isRead)
          .length ??
      0,
);

const _themeModeKey = 'kv_theme_mode';

/// ponytail: read once during startup so the first frame already paints the
/// saved theme. Ceiling: a plain global; move to an async bootstrap provider if
/// more startup settings appear.
ThemeMode bootThemeMode = ThemeMode.system;

Future<ThemeMode> loadThemeMode() async {
  final stored = (await SharedPreferences.getInstance()).getString(
    _themeModeKey,
  );
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == stored,
    orElse: () => ThemeMode.system,
  );
}

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => bootThemeMode;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    bootThemeMode = mode;
    (await SharedPreferences.getInstance()).setString(_themeModeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

void refreshVault(WidgetRef ref) {
  ref.invalidate(memberProvider);
  ref.invalidate(documentsProvider);
  ref.invalidate(passwordsProvider);
  ref.invalidate(linksProvider);
  ref.invalidate(imagesProvider);
  ref.invalidate(signaturesProvider);
  ref.invalidate(membersProvider);
  ref.invalidate(invitesProvider);
  ref.invalidate(activityProvider);
  ref.invalidate(notesProvider);
  ref.invalidate(todosProvider);
  ref.invalidate(notificationsProvider);
}
