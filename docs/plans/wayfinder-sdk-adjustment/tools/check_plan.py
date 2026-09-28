"""Check planning structure, not implementation or runtime correctness."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
data = json.loads((root / "task-manifest.json").read_text(encoding="utf-8"))
tasks = data["tasks"]
by_id = {task["id"]: task for task in tasks}


def require(condition, message):
    if not condition:
        raise ValueError(message)


require(bool(tasks), "No work items")
require(len(by_id) == len(tasks), "Duplicate ticket IDs")
require(data["active_batch"] == "A", "Unexpected active batch")
require(data["active_tasks"] == ["W01", "W02", "W03"], "Unexpected active scope")
paths = [task["path"] for task in tasks]
require(len(set(paths)) == len(paths), "Duplicate ticket paths")
require(
    {p.relative_to(root).as_posix() for p in (root / "tickets").glob("*.md")}
    == set(paths),
    "Manifest and ticket directory differ",
)
seen = set()
visiting = set()


def visit(key):
    require(key in by_id, f"Unknown dependency: {key}")
    require(key not in visiting, f"Dependency cycle at {key}")
    if key in seen:
        return
    visiting.add(key)
    task = by_id[key]
    require(re.fullmatch(r"[A-Z]+[0-9]{2}", key), f"Invalid ticket ID: {key}")
    path = (root / task["path"]).resolve()
    require(root in path.parents, f"Ticket escapes adjustment directory: {key}")
    require(path.is_file(), f"Missing ticket: {path}")
    text = path.read_text(encoding="utf-8")
    require(text.startswith(f"# {key} — {task['title']}\n"), f"Title mismatch: {key}")
    for label, field in (("Batch", "batch"), ("Status", "status")):
        match = re.search(rf"^\*\*{label}:\*\* (.+)$", text, re.MULTILINE)
        require(match is not None, f"Missing {label}: {key}")
        require(match.group(1).strip() == task[field], f"{label} mismatch: {key}")
    blocked = re.search(r"^\*\*Blocked by:\*\* (.+)$", text, re.MULTILINE)
    require(blocked is not None, f"Missing blockers: {key}")
    blocker_ids = re.findall(r"\b[A-Z]+[0-9]{2}\b", blocked.group(1))
    require(blocker_ids == task["blocked_by"], f"Blocker mismatch: {key}")
    for heading in (
        "What to build", "Scope", "Acceptance criteria",
        "Out of scope and external gates", "Test and demonstration evidence",
        "Review and handoff",
    ):
        require(f"## {heading}" in text, f"Missing {heading}: {key}")
    require("- [ ]" in text, f"No acceptance criteria: {key}")
    for blocker in task["blocked_by"]:
        visit(blocker)
    visiting.remove(key)
    seen.add(key)


for key in by_id:
    visit(key)
for key in data["active_tasks"]:
    task = by_id[key]
    require(task["batch"] == data["active_batch"], f"Active batch mismatch: {key}")
    require(task["status"] == "ready-for-agent", f"Active status mismatch: {key}")
    require(set(task["blocked_by"]) <= set(data["active_tasks"]), f"External active blocker: {key}")
master = (root / "ADJUSTMENT.md").read_text(encoding="utf-8")
for task in tasks:
    require(master.count(f"({task['path']})") == 1, f"Missing/duplicate adjustment link: {task['id']}")
for path in root.rglob("*.md"):
    text = path.read_text(encoding="utf-8")
    require(len(re.findall(r"^```", text, re.MULTILINE)) % 2 == 0, f"Unbalanced code fences: {path}")
print(f"PASS: {len(tasks)} tickets; acyclic dependencies; metadata, active scope, and adjustment links consistent")
