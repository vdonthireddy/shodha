#!/usr/bin/env python3
import sys
import json
import os
import uuid
import re
from datetime import datetime, timedelta

STORAGE_DIR = os.path.expanduser("~/Library/Application Support/Shodha")
OLD_STORAGE_DIR = os.path.expanduser("~/Library/Application Support/EchoBuddy")
os.makedirs(STORAGE_DIR, exist_ok=True)

# Migrate old reminders if new file does not exist yet
REMINDERS_FILE = os.path.join(STORAGE_DIR, "reminders.json")
old_reminders = os.path.join(OLD_STORAGE_DIR, "reminders.json")
if not os.path.exists(REMINDERS_FILE) and os.path.exists(old_reminders):
    try:
        import shutil
        shutil.copyfile(old_reminders, REMINDERS_FILE)
    except Exception:
        pass

def load_reminders():
    if not os.path.exists(REMINDERS_FILE):
        return []
    try:
        with open(REMINDERS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []

def save_reminders(reminders):
    with open(REMINDERS_FILE, "w", encoding="utf-8") as f:
        json.dump(reminders, f, indent=2)

def parse_target_time(target_str, now=None):
    if now is None:
        now = datetime.now()
    target_str = target_str.strip()
    target_lower = target_str.lower()
    
    # Phrases like "in an hour", "in a minute", "in half an hour"
    if "half an hour" in target_lower or "half-hour" in target_lower:
        return now + timedelta(minutes=30)
    if "an hour" in target_lower or "one hour" in target_lower:
        return now + timedelta(hours=1)
    if "a minute" in target_lower or "one minute" in target_lower:
        return now + timedelta(minutes=1)

    # Relative e.g. "30 seconds from now", "in 5 minutes", "after 2 hours", "10 seconds", "in 1 day"
    rel_match = re.search(r'(\d+)\s*(m|min|minute|minutes|h|hr|hour|hours|s|sec|second|seconds|d|day|days)', target_str, re.IGNORECASE)
    if rel_match and ("in " in target_lower or "from now" in target_lower or "after " in target_lower or "later" in target_lower or not any(x in target_lower for x in [":", "-", "/", "am", "pm"])):
        val = int(rel_match.group(1))
        unit = rel_match.group(2).lower()
        if unit.startswith('s'):
            return now + timedelta(seconds=val)
        elif unit.startswith('h'):
            return now + timedelta(hours=val)
        elif unit.startswith('d'):
            return now + timedelta(days=val)
        else:
            return now + timedelta(minutes=val)
            
    # "tomorrow at 3pm", "tomorrow 15:00"
    if "tomorrow" in target_lower:
        base_day = now + timedelta(days=1)
        sub = re.sub(r'tomorrow\s*(at)?\s*', '', target_str, flags=re.IGNORECASE).strip()
        if sub:
            for tf in ['%I:%M %p', '%I %p', '%I:%M%p', '%I%p', '%H:%M', '%H:%M:%S']:
                try:
                    dt = datetime.strptime(sub, tf)
                    return base_day.replace(hour=dt.hour, minute=dt.minute, second=dt.second, microsecond=0)
                except Exception:
                    pass
        return base_day.replace(hour=9, minute=0, second=0, microsecond=0)

    # Try ISO
    try:
        clean_iso = target_str.replace("Z", "+00:00")
        return datetime.fromisoformat(clean_iso)
    except Exception:
        pass

    formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d %I:%M %p",
        "%Y-%m-%d %I:%M:%S %p",
        "%Y-%m-%d %I%p",
        "%m/%d/%Y %H:%M:%S",
        "%m/%d/%Y %H:%M",
        "%m/%d/%Y %I:%M %p",
        "%m/%d/%Y %I:%M:%S %p",
        "%B %d, %Y %I:%M %p",
        "%B %d, %Y %H:%M",
        "%b %d, %Y %I:%M %p",
        "%b %d, %Y %H:%M",
        "%I:%M %p",
        "%I:%M:%S %p",
        "%I %p",
        "%I:%M%p",
        "%I%p",
        "%H:%M",
        "%H:%M:%S"
    ]
    for fmt in formats:
        try:
            dt = datetime.strptime(target_str, fmt)
            if fmt in ["%I:%M %p", "%I:%M:%S %p", "%I %p", "%I:%M%p", "%I%p", "%H:%M", "%H:%M:%S"]:
                dt = now.replace(hour=dt.hour, minute=dt.minute, second=dt.second, microsecond=0)
                if dt < now:
                    dt += timedelta(days=1)
            return dt
        except Exception:
            continue
            
    return None

def handle_schedule_reminder(args):
    reminder_text = args.get("reminder", "").strip()
    target_time_str = args.get("target_time", "").strip()
    
    if not reminder_text:
        return {"error": "Missing 'reminder' argument."}
    if not target_time_str:
        return {"error": "Missing 'target_time' argument."}
        
    now = datetime.now()
    dt = parse_target_time(target_time_str, now)
    if not dt:
        return {"error": f"Could not parse target date/time: '{target_time_str}'. Please provide ISO 8601 or relative format."}
        
    target_epoch = dt.timestamp()
    formatted_target = dt.strftime("%A, %b %d at %I:%M %p")
    
    diff_sec = int(target_epoch - now.timestamp())
    time_hint = ""
    if diff_sec > 0:
        minutes = diff_sec // 60
        hours = minutes // 60
        if hours > 0:
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
        "fired": False
    }
    
    reminders = load_reminders()
    reminders.append(reminder_obj)
    save_reminders(reminders)
    
    return {
        "status": "success",
        "message": f"Reminder scheduled: '{reminder_text}' for {formatted_target}{time_hint}.",
        "reminder_id": reminder_obj["id"],
        "target_time": dt.isoformat()
    }

def handle_list_reminders():
    reminders = load_reminders()
    now_epoch = datetime.now().timestamp()
    active = [r for r in reminders if not r.get("fired", False) and r.get("target_epoch", 0) > now_epoch]
    if not active:
        return {"reminders": [], "message": "No active reminders."}
    return {
        "count": len(active),
        "reminders": [
            {
                "id": r["id"],
                "text": r["text"],
                "time": r.get("formatted_time", r.get("target_iso", ""))
            } for r in active
        ]
    }

def handle_cancel_reminder(args):
    reminder_id = args.get("reminder_id", "").strip().lower()
    reminders = load_reminders()
    new_list = []
    cancelled = False
    for r in reminders:
        if r["id"].lower() == reminder_id or reminder_id in r["text"].lower():
            cancelled = True
        else:
            new_list.append(r)
    save_reminders(new_list)
    return {"status": "success" if cancelled else "not_found", "cancelled": cancelled}

TOOLS = [
    {
        "name": "schedule_reminder",
        "description": "Schedule a reminder for a specific date and time. Use this whenever the user asks to be reminded about something at a certain date, time, or in a duration.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "reminder": {
                    "type": "string",
                    "description": "The task or message to remind the user about."
                },
                "target_time": {
                    "type": "string",
                    "description": "The exact date and time in ISO format (YYYY-MM-DDTHH:MM:SS) or relative format (e.g. 'in 15 minutes', '2026-10-10T14:30:00')."
                }
            },
            "required": ["reminder", "target_time"]
        }
    },
    {
        "name": "list_reminders",
        "description": "List all active, upcoming scheduled reminders.",
        "inputSchema": {
            "type": "object",
            "properties": {}
        }
    },
    {
        "name": "cancel_reminder",
        "description": "Cancel a scheduled reminder by its ID or by text description.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "reminder_id": {
                    "type": "string",
                    "description": "The ID or description of the reminder to cancel."
                }
            },
            "required": ["reminder_id"]
        }
    }
]

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
        params = req.get("params", {})
        
        # Handle MCP Methods
        if method == "initialize":
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {
                        "tools": {}
                    },
                    "serverInfo": {
                        "name": "shodha-scheduler-mcp",
                        "version": "1.0.0"
                    }
                }
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        elif method == "notifications/initialized":
            # Notification, no response required
            pass
        elif method == "tools/list":
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "tools": TOOLS
                }
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        elif method == "tools/call":
            tool_name = params.get("name")
            args = params.get("arguments", {})
            if tool_name == "schedule_reminder":
                output = handle_schedule_reminder(args)
            elif tool_name == "list_reminders":
                output = handle_list_reminders()
            elif tool_name == "cancel_reminder":
                output = handle_cancel_reminder(args)
            else:
                output = {"error": f"Unknown tool '{tool_name}'"}
                
            res = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps(output)
                        }
                    ]
                }
            }
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        else:
            if req_id is not None:
                err_res = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {
                        "code": -32601,
                        "message": f"Method not found: {method}"
                    }
                }
                sys.stdout.write(json.dumps(err_res) + "\n")
                sys.stdout.flush()

if __name__ == "__main__":
    main()
