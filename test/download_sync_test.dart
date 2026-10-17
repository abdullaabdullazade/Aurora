import 'dart:io';
import 'dart:ui';

import 'package:aurora_music/core/db/local_store.dart';
import 'package:aurora_music/domain/entities/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

Track _track(String id) => Track(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      artworkUrl: '',
      duration: const Duration(minutes: 3),
      accent: const Color(0xFF000000),
    );

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aurora_store_test');
    store = LocalStore();
    await store.init(hivePath: dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Map<String, dynamic> remoteState({
    List<Map<String, dynamic>> downloads = const [],
    Map<String, int> deleted = const {},
  }) =>
      {'downloads': downloads, 'deletedDownloads': deleted};

  Map<String, dynamic> remoteDownload(String id, int at) =>
      {..._track(id).toJson(), 'downloadedAt': at};

  test('a deleted download is not restored from a stale snapshot', () async {
    await store.saveDownload(_track('aaaaaaaaaaa'));
    final stale = store.syncState(); // other device still has it
    await store.removeDownload('aaaaaaaaaaa');

    final desired = await store.mergeSyncState({
      'downloads': stale['downloads'],
    });

    expect(desired, isEmpty);
    expect(store.downloads(), isEmpty);
  });

  test('a deletion on another device removes the local download', () async {
    await store.saveDownload(_track('bbbbbbbbbbb'));
    final later = DateTime.now().millisecondsSinceEpoch + 1000;

    await store.mergeSyncState(remoteState(deleted: {'bbbbbbbbbbb': later}));

    expect(store.downloads(), isEmpty);
    expect(store.syncState()['deletedDownloads'], {'bbbbbbbbbbb': later});
  });

  test('downloading again after a deletion wins', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final desired = await store.mergeSyncState(remoteState(
      downloads: [remoteDownload('ccccccccccc', now)],
      deleted: {'ccccccccccc': now - 1000},
    ));

    expect(desired.map((t) => t.id), ['ccccccccccc']);
    expect(store.downloads().map((t) => t.id), ['ccccccccccc']);
  });

  test('auto downloads keep their flag through sync', () async {
    await store.saveDownload(_track('ddddddddddd'), auto: true);
    final snapshot = store.syncState();
    expect(store.isAutoDownload('ddddddddddd'), isTrue);

    await Hive.deleteFromDisk();
    await Hive.close();
    store = LocalStore();
    await store.init(hivePath: dir.path);
    await store.mergeSyncState(snapshot);

    expect(store.isAutoDownload('ddddddddddd'), isTrue);
  });
}
