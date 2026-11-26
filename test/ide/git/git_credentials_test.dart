import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/ide/git/git_credentials.dart';
import 'package:baocode/ide/git/git_service.dart';

void main() {
  tearDown(() {
    IdeGitCredentials.instance
      ..prompter = null
      ..clear();
  });

  test('an HTTPS remote Git could not ask for is in its failure', () {
    final output = IdeGitOutput(
      128,
      '',
      "fatal: could not read Username for 'https://172.16.11.238': "
          'terminal prompts disabled',
    );
    expect(IdeGitCredentials.hostIn(output), 'https://172.16.11.238');
  });

  test("a refused password is the host's too", () {
    final output = IdeGitOutput(
      128,
      '',
      "fatal: Authentication failed for 'https://10.0.0.2:8443/git/app/'",
    );
    expect(IdeGitCredentials.hostIn(output), 'https://10.0.0.2:8443');
  });

  test('another failure asks for nothing', () {
    expect(
      IdeGitCredentials.hostIn(IdeGitOutput(1, '', "error: 不能获取 origin")),
      isNull,
    );
    expect(IdeGitCredentials.hostIn(IdeGitOutput(0, '', '')), isNull);
  });

  test('the credentials go to that host alone', () {
    final arguments = IdeGitCredentials.arguments(
      'https://172.16.11.238',
      const IdeGitCredential('leo', 's3cret'),
    );
    expect(arguments, [
      '-c',
      'http.https://172.16.11.238/.extraHeader=Authorization: Basic '
          '${base64Encode(utf8.encode('leo:s3cret'))}',
    ]);
  });

  test('a host is asked once, until its credentials are forgotten', () async {
    var asked = 0;
    IdeGitCredentials.instance.prompter = (host) async {
      asked++;
      return const IdeGitCredential('leo', 's3cret');
    };
    final first = await IdeGitCredentials.instance.forHost(
      'https://172.16.11.238',
    );
    final again = await IdeGitCredentials.instance.forHost(
      'https://172.16.11.238',
    );
    expect(asked, 1);
    expect(first?.username, 'leo');
    expect(again?.password, 's3cret');
    IdeGitCredentials.instance.forget('https://172.16.11.238');
    await IdeGitCredentials.instance.forHost('https://172.16.11.238');
    expect(asked, 2);
  });

  test(
    'a command that could not ask runs again with the credentials',
    () async {
      var calls = 0;
      final service = IdeGitService(
        '/repo',
        runner:
            (
              arguments, {
              required workingDirectory,
              limit,
              stdin,
              environment,
            }) async {
              calls++;
              if (calls == 1) {
                return IdeGitOutput(
                  128,
                  '',
                  "fatal: could not read Username for 'https://172.16.11.238': "
                      'terminal prompts disabled',
                );
              }
              expect(arguments, contains(startsWith('http.https://')));
              return IdeGitOutput(0, '', '');
            },
      );
      IdeGitCredentials.instance.prompter = (_) async =>
          const IdeGitCredential('leo', 's3cret');
      final output = await service.run(['fetch', '--all', '--tags']);
      expect(calls, 2);
      expect(output.exitCode, 0);
    },
  );

  test('a refused credential is asked for again next time', () async {
    var calls = 0;
    final service = IdeGitService(
      '/repo',
      runner:
          (
            arguments, {
            required workingDirectory,
            limit,
            stdin,
            environment,
          }) async {
            calls++;
            return IdeGitOutput(
              128,
              '',
              "fatal: Authentication failed for 'https://172.16.11.238/app/'",
            );
          },
    );
    var asked = 0;
    IdeGitCredentials.instance.prompter = (_) async {
      asked++;
      return const IdeGitCredential('leo', 'wrong');
    };
    await service.run(['fetch']);
    await service.run(['fetch']);
    expect(calls, 4);
    expect(asked, 2);
  });
}
