// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:convert';

import 'package:boundary/oauth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/sut_factory.dart';

void main() {
  late DateTime clock;
  late SharedPreferencesPostAuthRedirectStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime.utc(2026, 10, 20, 9, 0, 0);
    store = SutFactory.createSharedPreferencesRedirectStore(now: () => clock);
  });

  test('the redirect store gives a URI once', () async {
    await store.save(Uri.parse('/cases/7'));

    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString('post_auth_redirect_intent')!),
      {
        'uri': '/cases/7',
        'timestamp': DateTime.utc(2026, 10, 20, 9).millisecondsSinceEpoch,
      },
    );
    expect(await store.take(), Uri.parse('/cases/7'));
    expect(await store.take(), isNull);
  });

  test('the redirect store expires after five minutes', () async {
    await store.save(Uri.parse('/cases/7'));

    clock = DateTime.utc(2026, 10, 20, 9, 5, 1);
    expect(await store.take(), isNull);

    clock = DateTime.utc(2026, 10, 20, 9, 0, 0);
    await store.save(Uri.parse('/cases/7'));
    clock = DateTime.utc(2026, 10, 20, 9, 5, 0);
    expect(await store.take(), Uri.parse('/cases/7'));
  });

  test('a malformed redirect value gives null and removes the key', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('post_auth_redirect_intent', '{');

    expect(await store.take(), isNull);
    expect(prefs.containsKey('post_auth_redirect_intent'), isFalse);
  });
}
