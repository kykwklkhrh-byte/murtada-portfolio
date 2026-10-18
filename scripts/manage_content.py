#!/usr/bin/env python3
"""Apply GitHub-Issue edits from the authenticated repository owner."""
import json
import os
import re
import uuid
from pathlib import Path
from urllib.parse import urlparse

DB = Path("data.json")
body = os.getenv("ISSUE_BODY", "")
if len(body) > 25000:
    raise ValueError("الطلب أطول من الحد المسموح.")
match = re.search(r"PORTFOLIO_REQUEST_V1\s*BEGIN_REQUEST\s*(.*?)\s*END_REQUEST", body, re.S)
if not match:
    raise ValueError("لم يتم العثور على طلب الإدارة.")
req = json.loads(match.group(1))
if not isinstance(req, dict):
    raise ValueError("الطلب غير صالح.")

def text(v, limit=500):
    if not isinstance(v, (str, int, float)):
        return ""
    return re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", str(v)).strip()[:limit]

def link(v):
    s = text(v, 1800)
    if not s:
        return ""
    parsed = urlparse(s)
    if parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password:
        return s
    raise ValueError("الروابط يجب أن تبدأ بـ https://")

data = json.loads(DB.read_text(encoding="utf-8"))
projects = data.get("projects", [])
if not isinstance(projects, list):
    raise ValueError("ملف المشاريع غير صالح")

def find_project():
    key = text(req.get("id"), 90)
    for project in projects:
        if project.get("id") == key:
            return project
    raise ValueError("المشروع المطلوب غير موجود؛ حدّث صفحة الإدارة")

def update_project(p):
    name = text(req.get("name"), 120)
    description = text(req.get("description"), 1000)
    if not name or not description:
        raise ValueError("اكتب اسم المشروع ووصفه")
    p["name"] = name
    p["description"] = description
    category = text(req.get("type"), 40)
    if category not in ("تطبيق", "موقع", "لعبة"):
        raise ValueError("نوع المشروع غير صحيح")
    p["type"] = category
    state = text(req.get("status"), 40)
    if state not in ("قيد التطوير", "نسخة تجريبية", "منشور"):
        raise ValueError("حالة المشروع غير صحيحة")
    p["status"] = state
    p["link"] = link(req.get("link"))
    picture = text(req.get("image"), 1800)
    if not picture:
        attached = re.search(r"!\[[^\]]*\]\((https://[^)\s]+)\)", body)
        if attached:
            picture = attached.group(1)
    p["image"] = link(picture)
    tags = req.get("tags", [])
    if isinstance(tags, str):
        tags = re.split(r"[,،]", tags)
    p["tags"] = [text(t, 35) for t in tags[:8] if text(t, 35)] if isinstance(tags, list) else []

op = req.get("operation")
if op == "add":
    if len(projects) >= 100:
        raise ValueError("عدد المشاريع بلغ الحد الأعلى")
    p = {"id": "p-" + uuid.uuid4().hex[:12], "art": "custom"}
    update_project(p)
    projects.insert(0, p)
elif op == "edit":
    update_project(find_project())
elif op == "delete":
    projects.remove(find_project())
elif op == "profile":
    for k, mx in {"name":100,"title":150,"bio":500,"about":1300,"location":100,"email":150,"whatsapp":30}.items():
        if k in req:
            data[k] = text(req[k], mx)
    for k in ("github", "instagram"):
        if k in req:
            data[k] = link(req[k])
    picture = text(req.get("photo"), 1800)
    if not picture:
        attached = re.search(r"!\[[^\]]*\]\((https://[^)\s]+)\)", body)
        if attached:
            picture = attached.group(1)
    if picture:
        data["photo"] = link(picture)
else:
    raise ValueError("عملية غير معروفة")

data["projects"] = projects
DB.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("Updated:", op, "projects:", len(projects))
