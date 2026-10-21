import 'package:clinic_appointment_system/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _FakeUserAttributes extends Fake implements UserAttributes {}

void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late AuthRepository repository;
  final failure = Exception('auth failure');

  setUpAll(() {
    registerFallbackValue(_FakeUserAttributes());
  });

  setUp(() {
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    repository = AuthRepository(client: client);
  });

  group('sign up', () {
    test('forwards credentials and propagates Supabase errors', () async {
      when(
        () => auth.signUp(email: 'patient@example.com', password: 'password'),
      ).thenThrow(failure);

      await expectLater(
        repository.signUp(
          email: 'patient@example.com',
          password: 'password',
        ),
        throwsA(same(failure)),
      );

      verify(
        () => auth.signUp(email: 'patient@example.com', password: 'password'),
      ).called(1);
    });
  });

  group('sign in', () {
    test('forwards credentials and propagates Supabase errors', () async {
      when(
        () => auth.signInWithPassword(
          email: 'patient@example.com',
          password: 'password',
        ),
      ).thenThrow(failure);

      await expectLater(
        repository.signIn(
          email: 'patient@example.com',
          password: 'password',
        ),
        throwsA(same(failure)),
      );

      verify(
        () => auth.signInWithPassword(
          email: 'patient@example.com',
          password: 'password',
        ),
      ).called(1);
    });
  });

  test('sign out delegates to Supabase and propagates errors', () async {
    when(() => auth.signOut()).thenThrow(failure);

    await expectLater(repository.signOut(), throwsA(same(failure)));

    verify(() => auth.signOut()).called(1);
  });

  test('password reset delegates to Supabase and propagates errors', () async {
    when(
      () => auth.resetPasswordForEmail('patient@example.com'),
    ).thenThrow(failure);

    await expectLater(
      repository.requestPasswordReset(email: 'patient@example.com'),
      throwsA(same(failure)),
    );

    verify(
      () => auth.resetPasswordForEmail('patient@example.com'),
    ).called(1);
  });

  test('password update delegates to Supabase and propagates errors', () async {
    when(() => auth.updateUser(any())).thenThrow(failure);

    await expectLater(
      repository.updatePassword(password: 'new-password'),
      throwsA(same(failure)),
    );

    final attributes = verify(() => auth.updateUser(captureAny())).captured.single
        as UserAttributes;
    expect(attributes.password, 'new-password');
  });
}
