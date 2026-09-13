import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  // Tray notifications are an enhancement: a Firebase failure must not stop the
  // vault from opening.
  try {
    await Firebase.initializeApp();
  } catch (error) {
    debugPrint('Firebase unavailable, tray notifications disabled: $error');
  }
  bootThemeMode = await loadThemeMode();
  runApp(const ProviderScope(child: KashivVaultApp()));
}

class KashivVaultApp extends ConsumerWidget {
  const KashivVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'KASHIVWEALTH MANAGEMENT VAULT',
      debugShowCheckedModeBanner: false,
      theme: VaultTheme.light(),
      darkTheme: VaultTheme.dark(),
      themeMode: mode,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final session =
        auth.value?.session ?? Supabase.instance.client.auth.currentSession;
    if (auth.isLoading && session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session == null) {
      return const LoginScreen();
    }
    return ref
        .watch(memberProvider)
        .when(
          data: (_) => const HomeShell(),
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_person_outlined, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'Vault access required',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$error'.contains('not been invited')
                          ? 'An owner or administrator must invite this email before it can access company data.'
                          : 'Unable to open the vault.\n$error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(repositoryProvider).signOut(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
  }
}
