import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/core/session/session.dart';

/// Versioning like Tryton (specs/RELEASE.md): the app version is
/// `<series>.N`, the series (server major.minor, spec 2.9) has a single
/// place in the code ([kClientVersion]).
class _Server extends RpcClient {
  final String version;
  _Server(this.version) : super(baseUrl: 'http://localhost');

  @override
  Future<String> serverVersion() async => version;
}

void main() {
  test('major.minor of pubspec.yaml is the series of the code', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*(\d+)\.(\d+)\.\d+', multiLine: true)
            .firstMatch(pubspec);
    expect(version, isNotNull, reason: 'version x.y.z in pubspec.yaml');
    expect('${version!.group(1)}.${version.group(2)}', kClientVersion);
  });

  test('the default app version is the one of pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true)
        .firstMatch(pubspec)!
        .group(1);
    expect(kAppVersion, version);
    expect(kAppVersion, startsWith('$kClientVersion.'));
  });

  test('a server of the same series passes, another one is refused', () async {
    await TrytonSession(rpcClient: _Server('$kClientVersion.9'))
        .checkCompatibility();
    await expectLater(
        TrytonSession(rpcClient: _Server('7.6.3')).checkCompatibility(),
        throwsA(isA<VersionMismatchException>()
            .having((e) => e.serverVersion, 'server', '7.6')
            .having((e) => e.clientVersion, 'client', kClientVersion)));
  });
}
