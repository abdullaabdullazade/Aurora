import os
import tempfile
import threading
import time
import unittest
from concurrent.futures import Future

from fastapi import HTTPException
from fastapi.testclient import TestClient

import main


class PromoteDownloadTest(unittest.TestCase):
    def test_ignores_partial_downloads(self) -> None:
        with tempfile.TemporaryDirectory() as work:
            partial = os.path.join(work, "track.m4a.part")
            target = os.path.join(work, "cached.mp4")
            with open(partial, "wb") as file:
                file.write(b"incomplete")

            self.assertIsNone(main._promote_download(work, target))
            self.assertFalse(os.path.exists(target))

    def test_atomically_promotes_completed_media(self) -> None:
        with tempfile.TemporaryDirectory() as work:
            completed = os.path.join(work, "track.m4a")
            target = os.path.join(work, "cached.mp4")
            with open(completed, "wb") as file:
                file.write(b"complete audio")

            self.assertEqual(main._promote_download(work, target), target)
            with open(target, "rb") as file:
                self.assertEqual(file.read(), b"complete audio")
            self.assertFalse(os.path.exists(completed))


class ParseRangeTest(unittest.TestCase):
    def test_parses_normal_open_and_suffix_ranges(self) -> None:
        self.assertEqual(main._parse_range("bytes=2-5", 10), (2, 5))
        self.assertEqual(main._parse_range("bytes=7-", 10), (7, 9))
        self.assertEqual(main._parse_range("bytes=-3", 10), (7, 9))

    def test_rejects_unsatisfiable_ranges(self) -> None:
        for value in ("bytes=10-", "bytes=8-2", "bytes=-0", "not-a-range"):
            with self.subTest(value=value), self.assertRaises(HTTPException) as caught:
                main._parse_range(value, 10)
            self.assertEqual(caught.exception.status_code, 416)
            self.assertEqual(caught.exception.headers, {"Content-Range": "bytes */10"})


class LyricsMatchTest(unittest.TestCase):
    def setUp(self) -> None:
        self.identities = main._lyric_identities(
            "Adele - Hello (Official Video)", "AdeleVEVO"
        )

    def test_selects_identity_match_instead_of_first_synced_result(self) -> None:
        wrong = {
            "id": 1,
            "trackName": "Hello",
            "artistName": "Lionel Richie",
            "duration": 241,
            "syncedLyrics": "[00:01.00]Wrong song",
        }
        correct = {
            "id": 2,
            "trackName": "Hello",
            "artistName": "Adele",
            "duration": 295,
            "plainLyrics": "Correct song",
        }

        selected = main._select_lyric_hit(
            [wrong, correct], self.identities, duration=295
        )

        self.assertIs(selected, correct)

    def test_rejects_wrong_version_by_duration(self) -> None:
        live_version = {
            "trackName": "Hello",
            "artistName": "Adele",
            "duration": 360,
            "syncedLyrics": "[00:01.00]Live version",
        }

        self.assertIsNone(main._select_lyric_hit(
            [live_version], self.identities, duration=295
        ))

    def test_accepts_topic_channel_artist(self) -> None:
        identities = main._lyric_identities(
            "Blinding Lights", "The Weeknd - Topic"
        )
        hit = {
            "trackName": "Blinding Lights",
            "artistName": "The Weeknd",
            "duration": 200,
            "syncedLyrics": "[00:01.00]Yeah",
        }

        self.assertIs(main._select_lyric_hit([hit], identities, 200), hit)


class LyricsTimingTest(unittest.TestCase):
    def test_accepts_timestamps_that_fit_the_track(self) -> None:
        synced = [{"time": 1.2}, {"time": 396.6}]

        self.assertEqual(main._lyrics_timing(synced, 405), (True, None, None))

    def test_suggests_delay_for_probable_video_intro(self) -> None:
        synced = [{"time": 1.2}, {"time": 396.6}]

        reliable, issue, offset = main._lyrics_timing(synced, 489)

        self.assertFalse(reliable)
        self.assertEqual(issue, "possible_video_intro")
        self.assertAlmostEqual(offset, 84.4)

    def test_rejects_timestamps_beyond_short_edit(self) -> None:
        synced = [{"time": 1.2}, {"time": 396.6}]

        self.assertEqual(
            main._lyrics_timing(synced, 365),
            (False, "timestamps_outside_track", None),
        )


class EntryTest(unittest.TestCase):
    def test_flags_live_streams(self) -> None:
        self.assertTrue(main._entry({"id": "abcdefghijk", "live_status": "is_live"})["live"])
        self.assertTrue(main._entry({"id": "abcdefghijk", "is_live": True})["live"])
        self.assertFalse(main._entry({"id": "abcdefghijk", "duration": 200})["live"])


class ProgressiveStreamTest(unittest.TestCase):
    video_id = "abcdefghijk"

    def setUp(self) -> None:
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.download_dir = os.path.join(self.work.name, f".{self.video_id}-tmp")
        os.makedirs(self.download_dir)
        self.part = os.path.join(self.download_dir, f"{self.video_id}.m4a.part")
        patches = {
            "_CACHE_DIR": self.work.name,
            "_PROGRESSIVE_POLL": 0.01,
            "_PROGRESSIVE_START_TIMEOUT": 2.0,
            "_PROGRESSIVE_STALL_TIMEOUT": 2.0,
        }
        for name, value in patches.items():
            original = getattr(main, name)
            setattr(main, name, value)
            self.addCleanup(setattr, main, name, original)

    def _write(self, path: str, data: bytes) -> None:
        with open(path, "ab") as file:
            file.write(data)

    def test_progressive_ranges(self) -> None:
        self.assertTrue(main._is_progressive_range(None))
        self.assertTrue(main._is_progressive_range("bytes=0-"))
        self.assertTrue(main._is_progressive_range("bytes=0-1"))
        self.assertFalse(main._is_progressive_range("bytes=500-"))
        self.assertFalse(main._is_progressive_range("bytes=-100"))

    def test_finds_partial_download_of_the_video(self) -> None:
        self.assertIsNone(main._partial_download(self.video_id))
        self._write(self.part, b"x")
        self._write(os.path.join(self.download_dir, "other.m4a.part"), b"y")
        self.assertEqual(main._partial_download(self.video_id), self.part)

    def test_tails_until_download_completes(self) -> None:
        # A separate marker stands in for the .part path so the test also runs
        # on Windows, where an open file cannot be renamed.
        marker = os.path.join(self.download_dir, "marker")
        self._write(marker, b"")
        self._write(self.part, b"a" * 10)

        def writer() -> None:
            time.sleep(0.05)
            self._write(self.part, b"b" * 10)
            time.sleep(0.05)
            os.remove(marker)

        thread = threading.Thread(target=writer)
        thread.start()
        body = b"".join(
            main._tail_growing_file(open(self.part, "rb"), marker, None)
        )
        thread.join()
        self.assertEqual(body, b"a" * 10 + b"b" * 10)

    @unittest.skipIf(os.name == "nt", "open files cannot be unlinked on Windows")
    def test_aborts_when_attempt_is_discarded(self) -> None:
        self._write(self.part, b"a" * 10)
        chunks = main._tail_growing_file(open(self.part, "rb"), self.part, None)
        self.assertEqual(next(chunks), b"a" * 10)
        os.remove(self.part)
        with self.assertRaises(RuntimeError):
            next(chunks)

    @unittest.skipIf(os.name == "nt", "open files cannot be renamed on Windows")
    def test_finishes_after_rename_into_place(self) -> None:
        self._write(self.part, b"a" * 10)
        chunks = main._tail_growing_file(open(self.part, "rb"), self.part, None)
        self.assertEqual(next(chunks), b"a" * 10)
        self._write(self.part, b"b" * 5)
        os.replace(self.part, os.path.join(self.download_dir, "done.m4a"))
        self.assertEqual(b"".join(chunks), b"b" * 5)

    def _client(self, future: Future) -> TestClient:
        original = (
            main._cache_get, main._start_background_download, main._ensure_local
        )

        def restore() -> None:
            (main._cache_get, main._start_background_download,
             main._ensure_local) = original

        self.addCleanup(restore)
        main._cache_get = lambda video_id: None
        main._start_background_download = lambda video_id: future

        def no_blocking_download(video_id: str) -> str:
            raise AssertionError("progressive request must not wait for the file")

        main._ensure_local = no_blocking_download
        return TestClient(main.app)

    def test_probe_answers_from_first_bytes(self) -> None:
        self._write(self.part, b"\x00\x01rest")
        response = self._client(Future()).get(
            f"/stream?v={self.video_id}", headers={"Range": "bytes=0-1"}
        )
        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.headers["content-range"], "bytes 0-1/*")
        self.assertEqual(response.content, b"\x00\x01")

    def test_waits_for_first_bytes(self) -> None:
        threading.Timer(0.1, self._write, (self.part, b"\x00\x01")).start()
        response = self._client(Future()).get(
            f"/stream?v={self.video_id}", headers={"Range": "bytes=0-1"}
        )
        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.content, b"\x00\x01")

    def test_serves_file_when_download_finished_first(self) -> None:
        cached = os.path.join(self.work.name, f"{self.video_id}.mp4")
        self._write(cached, b"complete")
        future: Future = Future()
        future.set_result(cached)
        response = self._client(future).get(f"/stream?v={self.video_id}")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-length"], "8")
        self.assertEqual(response.content, b"complete")

    def test_mid_range_waits_for_full_file(self) -> None:
        cached = os.path.join(self.work.name, f"{self.video_id}.mp4")
        self._write(cached, b"0123456789")
        self._client(Future())
        main._ensure_local = lambda video_id: cached
        self._write(self.part, b"01")
        response = TestClient(main.app).get(
            f"/stream?v={self.video_id}", headers={"Range": "bytes=5-"}
        )
        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.headers["content-range"], "bytes 5-9/10")
        self.assertEqual(response.content, b"56789")



class SecurityTest(unittest.TestCase):
    def test_playlist_rejects_non_youtube_urls(self) -> None:
        client = TestClient(main.app)
        for url in (
            "http://169.254.169.254/latest/meta-data/",
            "http://127.0.0.1:8000/sync",
            "file:///etc/passwd",
            "https://youtube.com.evil.example/playlist?list=x",
        ):
            response = client.get("/playlist", params={"url": url})
            self.assertEqual(response.status_code, 400, url)

    def test_cookie_copy_is_removed_after_use(self) -> None:
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        master = os.path.join(work.name, "cookies.txt")
        with open(master, "w", encoding="utf-8") as fh:
            fh.write("# Netscape HTTP Cookie File\n")
        original = main._cookiefile
        main._cookiefile = lambda: master
        self.addCleanup(setattr, main, "_cookiefile", original)

        with main._ydl({}) as ydl:
            copy = ydl.params["cookiefile"]
            self.assertNotEqual(copy, master)
            self.assertTrue(os.path.exists(copy))
        self.assertFalse(os.path.exists(copy))
        self.assertTrue(os.path.exists(master))

    def test_secret_key_is_required_when_configured(self) -> None:
        original = os.environ.get("AURORA_SECRET_KEY")
        os.environ["AURORA_SECRET_KEY"] = "s3cret"
        self.addCleanup(
            lambda: os.environ.pop("AURORA_SECRET_KEY", None)
            if original is None
            else os.environ.__setitem__("AURORA_SECRET_KEY", original)
        )
        client = TestClient(main.app)
        self.assertEqual(client.get("/suggest?q=a").status_code, 401)
        self.assertEqual(
            client.get("/suggest?q=a", headers={"x-api-key": "wrong"}).status_code,
            401,
        )
        self.assertEqual(client.get("/health").status_code, 200)


class LockStripeTest(unittest.TestCase):
    def test_lock_files_are_bounded(self) -> None:
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        original = main._CACHE_DIR
        main._CACHE_DIR = work.name
        self.addCleanup(setattr, main, "_CACHE_DIR", original)
        legacy = os.path.join(work.name, ".abcdefghijk.lock")
        open(legacy, "w").close()

        main._remove_legacy_lock_files()
        for i in range(300):
            with main._cross_process_lock(f"video{i:06d}"):
                pass

        self.assertFalse(os.path.exists(legacy))
        locks = os.listdir(os.path.join(work.name, ".locks"))
        self.assertLessEqual(len(locks), main._LOCK_STRIPES)


class FlatExtractRetryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.calls: list[str | None] = []
        originals = (main._ydl, main._pick_proxy, main._mark_bad,
                     main._record_good)
        self.addCleanup(lambda: (
            setattr(main, "_ydl", originals[0]),
            setattr(main, "_pick_proxy", originals[1]),
            setattr(main, "_mark_bad", originals[2]),
            setattr(main, "_record_good", originals[3]),
        ))
        self.bad: list[str] = []
        pool = ["http://p1:1", "http://p2:2", "http://p3:3"]
        main._pick_proxy = lambda exclude=None: next(
            (p for p in pool if p not in (exclude or set())), None)
        main._mark_bad = self.bad.append
        main._record_good = lambda p: None

    def _fake_ydl(self, fail_for: set[str | None]):
        test = self

        class Fake:
            def __init__(self, opts):
                self.proxy = opts.get("proxy")

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return None

            def extract_info(self, target, download=False):
                test.calls.append(self.proxy)
                if self.proxy in fail_for:
                    raise RuntimeError("Unable to connect to proxy")
                return {"entries": []}

        return lambda opts, use_cookies=True: Fake(opts)

    def test_moves_past_dead_proxies(self) -> None:
        main._ydl = self._fake_ydl({"http://p1:1"})
        self.assertEqual(main._extract_flat("ytsearch1:x"), {"entries": []})
        self.assertEqual(self.calls, ["http://p1:1", "http://p2:2"])
        self.assertEqual(self.bad, ["http://p1:1"])

    def test_falls_back_to_direct(self) -> None:
        main._ydl = self._fake_ydl({"http://p1:1", "http://p2:2", "http://p3:3"})
        main._extract_flat("ytsearch1:x")
        self.assertEqual(self.calls[-1], None)
        self.assertEqual(len(self.calls), 4)


class RelatedTest(unittest.TestCase):
    def test_filters_seed_live_and_compilations(self) -> None:
        info = {"entries": [
            {"id": "seedseed123", "title": "seed", "duration": 200},
            {"id": "okokokok123", "title": "song", "duration": 210},
            {"id": "livelive123", "title": "live", "live_status": "is_live"},
            {"id": "longlong123", "title": "1 hour mix", "duration": 3600},
            {"id": "unknown1234", "title": "no duration"},
        ]}
        ids = [r["id"] for r in main._related_rows(info, "seedseed123")]
        self.assertEqual(ids, ["okokokok123", "unknown1234"])

    def test_rejects_bad_ids(self) -> None:
        response = TestClient(main.app).get("/related", params={"v": "../x"})
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
