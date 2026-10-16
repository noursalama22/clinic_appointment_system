import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> requestPasswordReset({required String email}) {
    return _client.auth.resetPasswordForEmail(email);
  }

  Future<UserResponse> updatePassword({required String password}) {
    return _client.auth.updateUser(UserAttributes(password: password));
  }
}
