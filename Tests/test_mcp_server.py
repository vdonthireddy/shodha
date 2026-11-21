import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "Resources"))

import mcp_scheduler_server as mcp  # noqa: E402


class TestParseTargetTime(unittest.TestCase):
    def setUp(self):
        # Friday, Nov 20, 2026 at 20:50:00
        self.now = datetime(2026, 11, 20, 20, 50, 0)

    def test_relative_single_and_compound(self):
        self.assertEqual(mcp.parse_target_time("in 15 minutes", self.now), self.now + timedelta(minutes=15))
        self.assertEqual(
            mcp.parse_target_time("in 1 hour and 30 minutes", self.now),
            self.now + timedelta(hours=1, minutes=30),
        )
        self.assertEqual(
            mcp.parse_target_time("1h 20m 10s", self.now),
            self.now + timedelta(hours=1, minutes=20, seconds=10),
        )
        self.assertEqual(mcp.parse_target_time("half an hour", self.now), self.now + timedelta(minutes=30))

    def test_no_false_relative_on_month_names(self):
        # '10may' must NOT parse as '10 minutes'
        res = mcp.parse_target_time("10may", self.now)
        self.assertNotEqual(res, self.now + timedelta(minutes=10))

    def test_named_times_and_weekdays(self):
        self.assertEqual(mcp.parse_target_time("noon", self.now), datetime(2026, 11, 21, 12, 0, 0))
        self.assertEqual(mcp.parse_target_time("midnight", self.now), datetime(2026, 11, 21, 0, 0, 0))
        self.assertEqual(mcp.parse_target_time("tomorrow at 3pm", self.now), datetime(2026, 11, 21, 15, 0, 0))
        self.assertEqual(mcp.parse_target_time("next monday 9am", self.now), datetime(2026, 11, 23, 9, 0, 0))
        self.assertEqual(mcp.parse_target_time("May 5, 2027 3pm", self.now), datetime(2027, 5, 5, 15, 0, 0))
        self.assertEqual(mcp.parse_target_time("tonight at 9:30pm", self.now), datetime(2026, 11, 20, 21, 30, 0))


class TestMCPTools(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.orig_reminders = mcp.REMINDERS_FILE
        self.orig_rem_lock = mcp.REMINDERS_LOCK_FILE
        self.orig_notes = mcp.NOTES_FILE
        self.orig_notes_lock = mcp.NOTES_LOCK_FILE

        mcp.REMINDERS_FILE = os.path.join(self.tmp_dir.name, "reminders.json")
        mcp.REMINDERS_LOCK_FILE = os.path.join(self.tmp_dir.name, ".reminders.lock")
        mcp.NOTES_FILE = os.path.join(self.tmp_dir.name, "notes.json")
        mcp.NOTES_LOCK_FILE = os.path.join(self.tmp_dir.name, ".notes.lock")

    def tearDown(self):
        mcp.REMINDERS_FILE = self.orig_reminders
        mcp.REMINDERS_LOCK_FILE = self.orig_rem_lock
        mcp.NOTES_FILE = self.orig_notes
        mcp.NOTES_LOCK_FILE = self.orig_notes_lock
        self.tmp_dir.cleanup()

    def test_schedule_list_and_safe_cancel(self):
        res1 = mcp.handle_schedule_reminder({"reminder": "Drink water", "target_time": "in 10 minutes", "recurrence": "hourly"})
        self.assertEqual(res1["status"], "success")
        self.assertEqual(res1["recurrence"], "hourly")

        res2 = mcp.handle_schedule_reminder({"reminder": "Stand up", "target_time": "in 20 minutes"})
        self.assertEqual(res2["status"], "success")

        listed = mcp.handle_list_reminders()
        self.assertEqual(listed["count"], 2)

        # Empty cancel must NOT delete all reminders
        bad_cancel = mcp.handle_cancel_reminder({"reminder_id": ""})
        self.assertFalse(bad_cancel["cancelled"])
        self.assertEqual(mcp.handle_list_reminders()["count"], 2)

        good_cancel = mcp.handle_cancel_reminder({"reminder_id": "water"})
        self.assertTrue(good_cancel["cancelled"])
        self.assertEqual(mcp.handle_list_reminders()["count"], 1)

    def test_calculate_safe_and_unsafe(self):
        ok = mcp.handle_calculate({"expression": "sqrt(144) + 2**5"})
        self.assertEqual(ok["status"], "success")
        self.assertEqual(ok["result"], 44.0)

        bad = mcp.handle_calculate({"expression": "__import__('os').system('echo hacked')"})
        self.assertEqual(bad["status"], "error")

    def test_notes_crud(self):
        s = mcp.handle_save_note({"title": "Groceries", "content": "Milk, eggs"})
        self.assertEqual(s["status"], "success")
        note_id = s["note"]["id"]

        l = mcp.handle_list_notes()
        self.assertEqual(l["count"], 1)

        d = mcp.handle_delete_note({"note_id": note_id})
        self.assertTrue(d["deleted"])
        self.assertEqual(mcp.handle_list_notes()["count"], 0)

    def test_stdio_mcp_protocol_roundtrip(self):
        script = os.path.join(REPO_ROOT, "Resources", "mcp_scheduler_server.py")
        proc = subprocess.Popen(
            [sys.executable, script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            requests = [
                {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05"}},
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
                {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "calculate", "arguments": {"expression": "6 * 7"}}},
                {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "get_current_time", "arguments": {}}},
            ]
            for req in requests:
                proc.stdin.write(json.dumps(req) + "\n")
            proc.stdin.flush()
            proc.stdin.close()

            lines = [json.loads(line) for line in proc.stdout.read().splitlines() if line.strip()]
            self.assertEqual(len(lines), 4)
            self.assertEqual(lines[0]["id"], 1)
            tool_names = {t["name"] for t in lines[1]["result"]["tools"]}
            self.assertTrue({"search_internet", "fetch_webpage", "schedule_reminder", "calculate", "save_note"}.issubset(tool_names))
            calc_payload = json.loads(lines[2]["result"]["content"][0]["text"])
            self.assertEqual(calc_payload["result"], 42)
            time_payload = json.loads(lines[3]["result"]["content"][0]["text"])
            self.assertEqual(time_payload["status"], "success")
        finally:
            if proc.stdout:
                proc.stdout.close()
            if proc.stderr:
                proc.stderr.close()
            proc.terminate()
            proc.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
