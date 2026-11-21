#!/usr/bin/env python3
import ast
import fcntl
import html
import json
import math
import operator
import os
import re
import sys
import tempfile
import urllib.parse
import urllib.request
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta

STORAGE_DIR = os.path.expanduser("~/Library/Application Support/Shodha")
OLD_STORAGE_DIR = os.path.expanduser("~/Library/Application Support/EchoBuddy")
os.makedirs(STORAGE_DIR, exist_ok=True)

# Migrate old reminders if new file does not exist yet
REMINDERS_FILE = os.path.join(STORAGE_DIR, "reminders.json")
REMINDERS_LOCK_FILE = os.path.join(STORAGE_DIR, ".reminders.lock")
NOTES_FILE = os.path.join(STORAGE_DIR, "notes.json")
NOTES_LOCK_FILE = os.path.join(STORAGE_DIR, ".notes.lock")

old_reminders = os.path.join(OLD_STORAGE_DIR, "reminders.json")
if not os.path.exists(REMINDERS_FILE) and os.path.exists(old_reminders):
    try:
        import shutil
        shutil.copyfile(old_reminders, REMINDERS_FILE)
    except Exception:
        pass


@contextmanager
def file_lock(lock_path):
    """Advisory file lock shared with Swift processes for safe concurrent access."""
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _load_json_list(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, list) else []
    except Exception:
        return []


def _save_json_list_atomic(path, items):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".tmp_", suffix=".json", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(items, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def load_reminders():
    return _load_json_list(REMINDERS_FILE)


def save_reminders(reminders):
    _save_json_list_atomic(REMINDERS_FILE, reminders)


def load_notes():
    return _load_json_list(NOTES_FILE)


def save_notes(notes):
    _save_json_list_atomic(NOTES_FILE, notes)


_TIME_ONLY_FORMATS = [
    "%I:%M:%S %p",
    "%I:%M %p",
    "%I %p",
    "%I:%M%p",
    "%I%p",
    "%H:%M:%S",
    "%H:%M",
]

_WEEKDAYS = {
    "monday": 0, "mon": 0,
    "tuesday": 1, "tue": 1, "tues": 1,
    "wednesday": 2, "wed": 2,
    "thursday": 3, "thu": 3, "thur": 3, "thurs": 3,
    "friday": 4, "fri": 4,
    "saturday": 5, "sat": 5,
    "sunday": 6, "sun": 6,
}


def _parse_time_component(time_str):
    """Parse a standalone time string (e.g. '3pm', '14:30', 'noon', 'midnight') -> (hour, minute, second) or None."""
    s = time_str.strip().lower()
    s = re.sub(r"^(at|by|around|for)\s+", "", s).strip()
    if s in ("noon", "midday"):
        return (12, 0, 0)
    if s == "midnight":
        return (0, 0, 0)
    for fmt in _TIME_ONLY_FORMATS:
        try:
            dt = datetime.strptime(s, fmt)
            return (dt.hour, dt.minute, dt.second)
        except ValueError:
            continue
    return None


def parse_target_time(target_str, now=None):
    if now is None:
        now = datetime.now()
    elif now.tzinfo is not None:
        now = now.astimezone().replace(tzinfo=None)

    target_str = target_str.strip()
    if not target_str:
        return None
    target_lower = target_str.lower()

    # Exact named moments
    if re.fullmatch(r"(?:at\s+)?(noon|midday)(?:\s+today)?", target_lower):
        dt = now.replace(hour=12, minute=0, second=0, microsecond=0)
        return dt if dt > now else dt + timedelta(days=1)
    if re.fullmatch(r"(?:at\s+)?midnight(?:\s+tonight)?", target_lower):
        return (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    if target_lower in ("this morning", "morning"):
        dt = now.replace(hour=9, minute=0, second=0, microsecond=0)
        return dt if dt > now else dt + timedelta(days=1)
    if target_lower in ("this afternoon", "afternoon"):
        dt = now.replace(hour=14, minute=0, second=0, microsecond=0)
        return dt if dt > now else dt + timedelta(days=1)
    if target_lower in ("this evening", "evening"):
        dt = now.replace(hour=18, minute=0, second=0, microsecond=0)
        return dt if dt > now else dt + timedelta(days=1)
    if target_lower in ("tonight",):
        dt = now.replace(hour=20, minute=0, second=0, microsecond=0)
        return dt if dt > now else dt + timedelta(days=1)

    # Named relative phrases
    if "half an hour" in target_lower or "half-hour" in target_lower or "half hour" in target_lower:
        return now + timedelta(minutes=30)
    if "quarter of an hour" in target_lower or "quarter hour" in target_lower:
        return now + timedelta(minutes=15)
    if re.search(r"\b(an|one)\s+hour\b", target_lower) and not re.search(r"\d+\s*(m|min|minute)", target_lower):
        return now + timedelta(hours=1)
    if re.search(r"\b(a|one)\s+minute\b", target_lower):
        return now + timedelta(minutes=1)

    # Relative durations (supports compound expressions like "in 1 hour and 30 minutes", "1h 30m")
    unit_pattern = re.compile(
        r"\b(\d+)\s*(weeks?|wks?|w|days?|d|hours?|hrs?|hr|h|minutes?|mins?|min|m|seconds?|secs?|sec|s)\b",
        re.IGNORECASE,
    )
    matches = list(unit_pattern.finditer(target_str))
    has_clock_or_date = any(x in target_lower for x in [":", "/", "am", "pm"]) or bool(
        re.search(r"\d{4}-\d{1,2}-\d{1,2}", target_lower)
    )
    has_rel_marker = any(x in target_lower for x in ["in ", "from now", "after ", "later"])
    if matches and (has_rel_marker or not has_clock_or_date):
        total_delta = timedelta()
        for m in matches:
            val = int(m.group(1))
            unit = m.group(2).lower()
            if unit.startswith("w"):
                total_delta += timedelta(weeks=val)
            elif unit.startswith("d"):
                total_delta += timedelta(days=val)
            elif unit.startswith("h"):
                total_delta += timedelta(hours=val)
            elif unit.startswith("s"):
                total_delta += timedelta(seconds=val)
            else:
                total_delta += timedelta(minutes=val)
        if total_delta.total_seconds() > 0:
            return now + total_delta

    # "day after tomorrow" / "tomorrow"
    if "day after tomorrow" in target_lower:
        base_day = now + timedelta(days=2)
        sub = re.sub(r"day\s+after\s+tomorrow\s*(?:at)?\s*", "", target_str, flags=re.IGNORECASE).strip()
        if sub:
            hm = _parse_time_component(sub)
            if hm:
                return base_day.replace(hour=hm[0], minute=hm[1], second=hm[2], microsecond=0)
        return base_day.replace(hour=9, minute=0, second=0, microsecond=0)

    if "tomorrow" in target_lower:
        base_day = now + timedelta(days=1)
        sub = re.sub(r"tomorrow\s*(?:at)?\s*", "", target_str, flags=re.IGNORECASE).strip()
        if sub:
            hm = _parse_time_component(sub)
            if hm:
                return base_day.replace(hour=hm[0], minute=hm[1], second=hm[2], microsecond=0)
        return base_day.replace(hour=9, minute=0, second=0, microsecond=0)

    # Weekday expressions: "next Monday", "on Friday at 5pm", "Monday 14:00"
    weekday_match = re.match(
        r"^(?:(next|this|on)\s+)?(" + "|".join(_WEEKDAYS.keys()) + r")\b(.*)$",
        target_lower,
    )
    if weekday_match:
        qualifier = weekday_match.group(1) or ""
        wd_idx = _WEEKDAYS[weekday_match.group(2)]
        rest = weekday_match.group(3).strip()
        hm = _parse_time_component(rest) if rest else (9, 0, 0)
        if hm is None:
            hm = (9, 0, 0)
        days_ahead = (wd_idx - now.weekday()) % 7
        candidate = (now + timedelta(days=days_ahead)).replace(
            hour=hm[0], minute=hm[1], second=hm[2], microsecond=0
        )
        if qualifier == "next":
            if days_ahead == 0:
                candidate += timedelta(days=7)
            else:
                # "next <weekday>" if already upcoming this week or next week; advance 7 if same day
                pass
        elif candidate <= now:
            candidate += timedelta(days=7)
        return candidate

    # Try ISO format (normalize timezone-aware to local naive datetime)
    try:
        clean_iso = target_str.replace("Z", "+00:00")
        dt = datetime.fromisoformat(clean_iso)
        if dt.tzinfo is not None:
            dt = dt.astimezone().replace(tzinfo=None)
        return dt
    except Exception:
        pass

    # Normalize phrases: strip prepositions ('at', 'by', 'on') and qualifiers ('today', 'tonight')
    is_today = bool(re.search(r"\b(today|tonight)\b", target_lower))
    clean_target = re.sub(r"\b(today|tonight)\b", "", target_str, flags=re.IGNORECASE).strip()
    clean_target = re.sub(r"^(at|on|by)\s+", "", clean_target, flags=re.IGNORECASE).strip()
    clean_target = re.sub(r"\s+(at)\s+", " ", clean_target, flags=re.IGNORECASE).strip()
    clean_target = re.sub(r",\s*", " ", clean_target).strip()
    clean_target = re.sub(r"\s+", " ", clean_target).strip()

    candidate_strings = [clean_target, target_str]

    formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d %I:%M:%S %p",
        "%Y-%m-%d %I:%M %p",
        "%Y-%m-%d %I:%M%p",
        "%Y-%m-%d %I %p",
        "%Y-%m-%d %I%p",
        "%m/%d/%Y %H:%M:%S",
        "%m/%d/%Y %H:%M",
        "%m/%d/%Y %I:%M:%S %p",
        "%m/%d/%Y %I:%M %p",
        "%m/%d/%Y %I%p",
        "%B %d %Y %I:%M:%S %p",
        "%B %d %Y %I:%M %p",
        "%B %d %Y %I:%M%p",
        "%B %d %Y %I %p",
        "%B %d %Y %I%p",
        "%B %d %Y %H:%M",
        "%b %d %Y %I:%M:%S %p",
        "%b %d %Y %I:%M %p",
        "%b %d %Y %I:%M%p",
        "%b %d %Y %I %p",
        "%b %d %Y %I%p",
        "%b %d %Y %H:%M",
        "%d %B %Y %I:%M %p",
        "%d %B %Y %H:%M",
        "%d %b %Y %I:%M %p",
        "%d %b %Y %H:%M",
    ]

    month_day_formats = [
        "%Y %B %d %I:%M %p",
        "%Y %B %d %I:%M%p",
        "%Y %B %d %I %p",
        "%Y %B %d %I%p",
        "%Y %B %d %H:%M",
        "%Y %b %d %I:%M %p",
        "%Y %b %d %I:%M%p",
        "%Y %b %d %I %p",
        "%Y %b %d %I%p",
        "%Y %b %d %H:%M",
    ]

    for cand in candidate_strings:
        if not cand:
            continue
        for fmt in formats:
            try:
                return datetime.strptime(cand, fmt)
            except ValueError:
                continue
        for fmt in month_day_formats:
            try:
                dt = datetime.strptime(f"{now.year} {cand}", fmt)
                if dt < now:
                    dt = datetime.strptime(f"{now.year + 1} {cand}", fmt)
                return dt
            except ValueError:
                continue
        hm = _parse_time_component(cand)
        if hm is not None:
            dt = now.replace(hour=hm[0], minute=hm[1], second=hm[2], microsecond=0)
            if not is_today and dt < now:
                dt += timedelta(days=1)
            return dt

    return None


def handle_schedule_reminder(args):
    reminder_text = str(args.get("reminder", "")).strip()
    target_time_str = str(args.get("target_time", "")).strip()
    recurrence = str(args.get("recurrence", "none") or "none").strip().lower()
    if recurrence not in ("none", "hourly", "daily", "weekdays", "weekly"):
        recurrence = "none"

    if not reminder_text:
        return {"error": "Missing 'reminder' argument."}
    if not target_time_str:
        return {"error": "Missing 'target_time' argument."}

    now = datetime.now()
    dt = parse_target_time(target_time_str, now)
    if not dt:
        return {
            "error": (
                f"Could not parse target date/time: '{target_time_str}'. "
                "Please provide ISO 8601 (YYYY-MM-DDTHH:MM:SS) or relative format (e.g. 'in 15 minutes')."
            )
        }

    target_epoch = dt.timestamp()
    formatted_target = dt.strftime("%A, %b %d at %I:%M %p")

    diff_sec = round(target_epoch - now.timestamp())
    time_hint = ""
    if diff_sec > 0:
        minutes = diff_sec // 60
        hours = minutes // 60
        days = hours // 24
        if days > 0:
            time_hint = f" (in ~{days}d {hours % 24}h)"
        elif hours > 0:
            time_hint = f" (in ~{hours}h {minutes % 60}m)"
        elif minutes > 0:
            time_hint = f" (in ~{minutes} minutes)"
        else:
            time_hint = f" (in {diff_sec} seconds)"

    reminder_obj = {
        "id": str(uuid.uuid4()),
        "text": reminder_text,
        "target_iso": dt.isoformat(),
        "target_epoch": target_epoch,
        "formatted_time": formatted_target,
        "created_at": now.isoformat(),
        "fired": False,
        "recurrence": recurrence,
    }

    with file_lock(REMINDERS_LOCK_FILE):
        reminders = load_reminders()
        reminders.append(reminder_obj)
        save_reminders(reminders)

    recur_label = f" [{recurrence}]" if recurrence != "none" else ""
    return {
        "status": "success",
        "message": f"Reminder scheduled{recur_label}: '{reminder_text}' for {formatted_target}{time_hint}.",
        "reminder_id": reminder_obj["id"],
        "target_time": dt.isoformat(),
        "recurrence": recurrence,
    }


def handle_list_reminders():
    with file_lock(REMINDERS_LOCK_FILE):
        reminders = load_reminders()
    now_epoch = datetime.now().timestamp()
    active = sorted(
        [r for r in reminders if not r.get("fired", False) and r.get("target_epoch", 0) > now_epoch],
        key=lambda r: r.get("target_epoch", 0),
    )
    if not active:
        return {"count": 0, "reminders": [], "message": "No active reminders."}

    lines = []
    for i, r in enumerate(active, 1):
        t = r.get("formatted_time", r.get("target_iso", ""))
        rec = r.get("recurrence", "none")
        rec_tag = f" ({rec})" if rec and rec != "none" else ""
        lines.append(f"{i}. {r['text']} — {t}{rec_tag}")

    return {
        "count": len(active),
        "reminders": [
            {
                "id": r["id"],
                "text": r["text"],
                "time": r.get("formatted_time", r.get("target_iso", "")),
                "recurrence": r.get("recurrence", "none"),
            }
            for r in active
        ],
        "message": "Active reminders:\n" + "\n".join(lines),
    }


def handle_cancel_reminder(args):
    reminder_id = str(args.get("reminder_id", "")).strip().lower()
    if not reminder_id:
        return {
            "status": "error",
            "cancelled": False,
            "message": "Please specify a reminder ID or description to cancel.",
        }

    with file_lock(REMINDERS_LOCK_FILE):
        reminders = load_reminders()
        new_list = []
        cancelled_items = []
        for r in reminders:
            rid = str(r.get("id", "")).lower()
            rtext = str(r.get("text", "")).lower()
            if rid == reminder_id or reminder_id in rtext:
                cancelled_items.append(r.get("text", rid))
            else:
                new_list.append(r)
        if cancelled_items:
            save_reminders(new_list)

    if cancelled_items:
        joined = ", ".join(f"'{t}'" for t in cancelled_items)
        return {
            "status": "success",
            "cancelled": True,
            "count": len(cancelled_items),
            "message": f"Cancelled reminder(s): {joined}.",
        }
    return {
        "status": "not_found",
        "cancelled": False,
        "message": f"No reminder matching '{args.get('reminder_id', '')}' was found.",
    }


def search_duckduckgo(query, max_results=5):
    url = "https://html.duckduckgo.com/html/?" + urllib.parse.urlencode({"q": query})
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
            )
        },
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        page = resp.read(1024 * 1024).decode("utf-8", errors="ignore")

    clean = lambda s: re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html.unescape(s))).strip()
    result_blocks = re.findall(
        r'<div[^>]*class=[\'"][^\'"]*result\s+results_links[^\'"]*[\'"][^>]*>(.*?)</div>\s*</div>\s*</div>',
        page,
        re.DOTALL,
    )
    results = []

    for block in result_blocks:
        title_match = re.search(
            r'<a[^>]*class=[\'"][^\'"]*result__a[^\'"]*[\'"][^>]*href=[\'"]([^\'"]+)[\'"][^>]*>(.*?)</a>',
            block,
            re.DOTALL,
        )
        if not title_match:
            continue
        href = title_match.group(1)
        title = clean(title_match.group(2))

        if "uddg=" in href:
            uddg_match = re.search(r"uddg=([^&]+)", href)
            if uddg_match:
                href = urllib.parse.unquote(uddg_match.group(1))
        elif href.startswith("//"):
            href = "https:" + href

        snippet_match = re.search(
            r'<a[^>]*class=[\'"][^\'"]*result__snippet[^\'"]*[\'"][^>]*>(.*?)</a>',
            block,
            re.DOTALL,
        )
        snippet = clean(snippet_match.group(1)) if snippet_match else ""

        results.append({"title": title, "url": href, "snippet": snippet})
        if len(results) >= max_results:
            break

    return results


def search_wikipedia(query, max_results=3):
    url = (
        "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch="
        f"{urllib.parse.quote(query)}&format=json&utf8=1&srlimit={max_results}"
    )
    req = urllib.request.Request(url, headers={"User-Agent": "ShodhaDesktopCompanion/1.0"})
    clean = lambda s: re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html.unescape(s))).strip()
    with urllib.request.urlopen(req, timeout=5) as resp:
        data = json.loads(resp.read(512 * 1024).decode("utf-8"))
        results = []
        for item in data.get("query", {}).get("search", []):
            title = item.get("title", "")
            results.append(
                {
                    "title": title,
                    "snippet": clean(item.get("snippet", "")),
                    "url": f"https://en.wikipedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}",
                }
            )
        return results


def fetch_page_content(url, max_chars=1200):
    if not url or not url.startswith(("http://", "https://")):
        return ""
    try:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
                )
            },
        )
        with urllib.request.urlopen(req, timeout=4.0) as resp:
            content_type = resp.headers.get("Content-Type", "").lower()
            if "text/html" not in content_type and "text/plain" not in content_type and "application/xhtml" not in content_type:
                return ""
            raw = resp.read(512 * 1024).decode("utf-8", errors="ignore")
            raw = re.sub(
                r"<(script|style|svg|noscript|header|footer|nav)[^>]*>.*?</\1>",
                " ",
                raw,
                flags=re.DOTALL | re.IGNORECASE,
            )
            text = re.sub(r"<[^>]+>", " ", raw)
            text = html.unescape(text)
            text = re.sub(r"\s+", " ", text).strip()
            return text[:max_chars]
    except Exception:
        return ""


def handle_search_internet(args):
    query = str(args.get("query", "")).strip()
    if not query:
        return {"status": "error", "message": "No search query provided."}

    try:
        max_res = max(1, min(10, int(args.get("max_results", 5))))
    except Exception:
        max_res = 5

    results = []
    try:
        results = search_duckduckgo(query, max_results=max_res)
    except Exception:
        pass

    if not results:
        try:
            results = search_wikipedia(query, max_results=max_res)
        except Exception:
            pass

    if not results:
        return {
            "status": "no_results",
            "query": query,
            "message": f"No web search results found for '{query}'.",
            "results": [],
        }

    # Enrich the top 2 results with live page content for deeper factual grounding
    for i in range(min(len(results), 2)):
        page_url = results[i].get("url", "")
        page_snippet = fetch_page_content(page_url, max_chars=1000)
        if page_snippet:
            results[i]["page_content"] = page_snippet

    summary_lines = []
    for i, r in enumerate(results, 1):
        line = f"{i}. [{r['title']}]({r['url']})\n   Summary: {r['snippet']}"
        if r.get("page_content"):
            line += f"\n   Page excerpt: {r['page_content'][:600]}..."
        summary_lines.append(line)

    return {
        "status": "success",
        "query": query,
        "count": len(results),
        "results": results,
        "message": f"Found {len(results)} search results for '{query}'.",
        "summary": "\n\n".join(summary_lines),
    }


def handle_fetch_webpage(args):
    url = str(args.get("url", "")).strip()
    if not url.startswith(("http://", "https://")):
        return {"status": "error", "message": "URL must start with http:// or https://."}
    try:
        max_chars = max(200, min(6000, int(args.get("max_chars", 2500))))
    except Exception:
        max_chars = 2500

    content = fetch_page_content(url, max_chars=max_chars)
    if not content:
        return {"status": "error", "url": url, "message": f"Could not extract readable text from {url}."}
    return {
        "status": "success",
        "url": url,
        "content": content,
        "message": f"Fetched content from {url}:\n\n{content}",
    }


_SAFE_BINOPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
}

_SAFE_UNARYOPS = {
    ast.UAdd: operator.pos,
    ast.USub: operator.neg,
}

_SAFE_FUNCS = {
    "abs": abs,
    "round": round,
    "min": min,
    "max": max,
    "sqrt": math.sqrt,
    "sin": math.sin,
    "cos": math.cos,
    "tan": math.tan,
    "log": math.log,
    "log10": math.log10,
    "log2": math.log2,
    "exp": math.exp,
    "ceil": math.ceil,
    "floor": math.floor,
    "factorial": math.factorial,
    "pow": pow,
}

_SAFE_CONSTS = {
    "pi": math.pi,
    "e": math.e,
    "tau": math.tau,
}


def _eval_math_node(node):
    if isinstance(node, ast.Expression):
        return _eval_math_node(node.body)
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.Name) and node.id in _SAFE_CONSTS:
        return _SAFE_CONSTS[node.id]
    if isinstance(node, ast.BinOp) and type(node.op) in _SAFE_BINOPS:
        left = _eval_math_node(node.left)
        right = _eval_math_node(node.right)
        if isinstance(node.op, ast.Pow) and abs(right) > 1000:
            raise ValueError("Exponent too large")
        return _SAFE_BINOPS[type(node.op)](left, right)
    if isinstance(node, ast.UnaryOp) and type(node.op) in _SAFE_UNARYOPS:
        return _SAFE_UNARYOPS[type(node.op)](_eval_math_node(node.operand))
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in _SAFE_FUNCS:
        if node.keywords:
            raise ValueError("Keyword arguments not supported")
        args = [_eval_math_node(a) for a in node.args]
        if node.func.id == "factorial" and (len(args) != 1 or args[0] > 1000 or args[0] < 0):
            raise ValueError("Factorial argument out of safe range (0..1000)")
        return _SAFE_FUNCS[node.func.id](*args)
    raise ValueError("Unsupported mathematical expression")


def handle_calculate(args):
    expr = str(args.get("expression", "")).strip()
    if not expr:
        return {"status": "error", "message": "Missing 'expression' argument."}
    if len(expr) > 200:
        return {"status": "error", "message": "Expression too long."}
    try:
        tree = ast.parse(expr, mode="eval")
        result = _eval_math_node(tree)
        if isinstance(result, float) and result.is_integer():
            formatted = str(int(result))
        else:
            formatted = str(result)
        return {
            "status": "success",
            "expression": expr,
            "result": result,
            "message": f"{expr} = {formatted}",
        }
    except Exception as exc:
        return {"status": "error", "expression": expr, "message": f"Calculation error: {exc}"}


def handle_get_current_time():
    now = datetime.now().astimezone()
    return {
        "status": "success",
        "iso": now.isoformat(),
        "formatted": now.strftime("%A, %B %d, %Y at %I:%M:%S %p %Z"),
        "timezone": str(now.tzinfo),
        "message": f"Current local time is {now.strftime('%A, %B %d, %Y at %I:%M %p %Z')}.",
    }


def handle_save_note(args):
    title = str(args.get("title", "")).strip()
    content = str(args.get("content", "")).strip()
    if not content and not title:
        return {"status": "error", "message": "Provide a title or content for the note."}
    if not title:
        title = content[:40] + ("..." if len(content) > 40 else "")

    note = {
        "id": str(uuid.uuid4())[:8],
        "title": title,
        "content": content or title,
        "created_at": datetime.now().isoformat(),
    }
    with file_lock(NOTES_LOCK_FILE):
        notes = load_notes()
        notes.append(note)
        save_notes(notes)

    return {
        "status": "success",
        "note": note,
        "message": f"Saved note [{note['id']}]: {note['title']}",
    }


def handle_list_notes():
    with file_lock(NOTES_LOCK_FILE):
        notes = load_notes()
    if not notes:
        return {"count": 0, "notes": [], "message": "No saved notes."}
    lines = [f"- [{n['id']}] {n['title']}: {n['content']}" for n in notes]
    return {
        "count": len(notes),
        "notes": notes,
        "message": "Saved notes:\n" + "\n".join(lines),
    }


def handle_delete_note(args):
    note_id = str(args.get("note_id", "")).strip().lower()
    if not note_id:
        return {"status": "error", "deleted": False, "message": "Specify a note ID or title to delete."}

    with file_lock(NOTES_LOCK_FILE):
        notes = load_notes()
        kept = []
        deleted = []
        for n in notes:
            nid = str(n.get("id", "")).lower()
            ntitle = str(n.get("title", "")).lower()
            if nid == note_id or note_id in ntitle:
                deleted.append(n.get("title", nid))
            else:
                kept.append(n)
        if deleted:
            save_notes(kept)

    if deleted:
        return {"status": "success", "deleted": True, "message": f"Deleted note(s): {', '.join(deleted)}."}
    return {"status": "not_found", "deleted": False, "message": f"No note matching '{args.get('note_id', '')}' found."}


TOOLS = [
    {
        "name": "search_internet",
        "description": "Search the live internet for up-to-date information, current news, facts, documentation, or when the user asks questions that require live web information.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "The search query keywords to search on the web (e.g. 'latest Apple news', 'weather San Francisco', 'Python 3.13 release date').",
                },
                "max_results": {
                    "type": "integer",
                    "description": "Maximum number of search results to retrieve (default is 5).",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "fetch_webpage",
        "description": "Fetch and extract readable plain text from a specific HTTP/HTTPS URL.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {
                    "type": "string",
                    "description": "The full http:// or https:// URL to read.",
                },
                "max_chars": {
                    "type": "integer",
                    "description": "Maximum number of characters to return (default 2500).",
                },
            },
            "required": ["url"],
        },
    },
    {
        "name": "schedule_reminder",
        "description": "Schedule a reminder for a specific date and time. Use this whenever the user asks to be reminded about something at a certain date, time, or in a duration.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "reminder": {
                    "type": "string",
                    "description": "The task or message to remind the user about.",
                },
                "target_time": {
                    "type": "string",
                    "description": "The date and time in ISO format (YYYY-MM-DDTHH:MM:SS) or natural/relative format (e.g. 'in 15 minutes', 'tomorrow at 9am', 'next Monday at 10:00').",
                },
                "recurrence": {
                    "type": "string",
                    "enum": ["none", "hourly", "daily", "weekdays", "weekly"],
                    "description": "Optional recurrence schedule (default 'none').",
                },
            },
            "required": ["reminder", "target_time"],
        },
    },
    {
        "name": "list_reminders",
        "description": "List all active, upcoming scheduled reminders.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "cancel_reminder",
        "description": "Cancel a scheduled reminder by its ID or by text description.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "reminder_id": {
                    "type": "string",
                    "description": "The ID or text description of the reminder to cancel.",
                }
            },
            "required": ["reminder_id"],
        },
    },
    {
        "name": "calculate",
        "description": "Evaluate a mathematical expression accurately (arithmetic, sqrt, sin, cos, log, factorial, pi, e).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "expression": {
                    "type": "string",
                    "description": "Mathematical expression, e.g. '(125 * 1.08) / 4' or 'sqrt(144) + 2**5'.",
                }
            },
            "required": ["expression"],
        },
    },
    {
        "name": "get_current_time",
        "description": "Get the exact current local date, time, day of week, and timezone.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "save_note",
        "description": "Save a quick persistent local note or scratchpad item for the user.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "description": "Short title for the note.",
                },
                "content": {
                    "type": "string",
                    "description": "Body text of the note.",
                },
            },
            "required": ["content"],
        },
    },
    {
        "name": "list_notes",
        "description": "List all saved local notes.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
    },
    {
        "name": "delete_note",
        "description": "Delete a saved local note by its ID or title.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "note_id": {
                    "type": "string",
                    "description": "The ID or title of the note to delete.",
                }
            },
            "required": ["note_id"],
        },
    },
]


TOOL_HANDLERS = {
    "search_internet": handle_search_internet,
    "fetch_webpage": handle_fetch_webpage,
    "schedule_reminder": handle_schedule_reminder,
    "list_reminders": lambda _args: handle_list_reminders(),
    "cancel_reminder": handle_cancel_reminder,
    "calculate": handle_calculate,
    "get_current_time": lambda _args: handle_get_current_time(),
    "save_note": handle_save_note,
    "list_notes": lambda _args: handle_list_notes(),
    "delete_note": handle_delete_note,
}


def main():
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            req = json.loads(line)
        except Exception:
            continue

        req_id = req.get("id")
        method = req.get("method")
        params = req.get("params", {}) or {}

        if method == "initialize":
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "shodha-scheduler-mcp", "version": "1.1.0"},
                },
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        elif method == "notifications/initialized":
            pass
        elif method == "tools/list":
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {"tools": TOOLS},
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        elif method == "tools/call":
            tool_name = params.get("name")
            args = params.get("arguments", {}) or {}
            handler = TOOL_HANDLERS.get(tool_name)
            if handler is not None:
                try:
                    output = handler(args)
                except Exception as exc:
                    output = {"error": f"Tool execution error: {exc}"}
            else:
                output = {"error": f"Unknown tool '{tool_name}'"}

            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(output)}]
                },
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        else:
            if req_id is not None:
                err_res = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": f"Method not found: {method}"},
                }
                sys.stdout.write(json.dumps(err_res) + "\n")
                sys.stdout.flush()


if __name__ == "__main__":
    main()
