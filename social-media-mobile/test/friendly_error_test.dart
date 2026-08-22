import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_chat_app/src/utils/friendly_error.dart';

void main() {
  test('the exact error from the screenshot becomes friendly', () {
    const raw = "ClientException with SocketException: Connection refused "
        "(OS Error: Connection refused, errno = 111), address = 10.0.2.2, "
        "port = 35548, uri=http://10.0.2.2:8090/api/social/posts/feed?page=0&size=20";
    final f = FriendlyError.from(Exception(raw));
    expect(f.title, 'No connection');
    expect(f.message.contains('10.0.2.2'), isFalse);
    expect(f.message.contains('8090'), isFalse);
    expect(f.message.contains('errno'), isFalse);
    print('  -> ${f.title}: ${f.message}');
  });

  test('typed socket + timeout', () {
    expect(FriendlyError.from(const SocketException('x')).title, 'No connection');
    expect(FriendlyError.from(TimeoutException('x')).title, 'Taking too long');
  });

  test('status codes map sensibly', () {
    expect(FriendlyError.from(Exception('Unauthorized')).title, 'Session expired');
    expect(FriendlyError.from(Exception('Forbidden')).title, 'Not available');
    expect(FriendlyError.from(Exception('Internal Server Error')).title,
        'Something went wrong');
  });

  test('unknown errors do not leak their text', () {
    final f = FriendlyError.from(Exception('secret internal detail xyzzy'));
    expect(f.message.contains('xyzzy'), isFalse);
    expect(f.title, 'Something went wrong');
  });
}
