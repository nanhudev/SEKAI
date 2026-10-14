"""Local (no-unreal) shape inspector for exports/p11_report.json.

Written because the build report mixes several key styles: some values are
plain strings, some are lists of dicts, and `plan` is a nested table. Guessing
the shape wastes UE launches, so this prints it once.
"""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "exports/p11_report.json"
r = json.load(open(path, encoding="utf-8"))

print("top keys:", list(r.keys()))
print()
sysd = r.get("systems")
print("systems type:", type(sysd).__name__)
if isinstance(sysd, list):
    for s in sysd:
        if isinstance(s, str):
            print("   str :", s)
        elif isinstance(s, dict):
            print("   dict:", list(s.keys()))
        else:
            print("   ", type(s).__name__, s)
print()
up = r.get("user_params")
print("user_params type:", type(up).__name__,
      "len", len(up) if hasattr(up, "__len__") else "-")
if isinstance(up, list) and up:
    print(json.dumps(up[:4], ensure_ascii=False, indent=1))
elif isinstance(up, dict):
    k = list(up.keys())[:8]
    print("keys:", k)
    print(json.dumps({k[0]: up[k[0]]}, ensure_ascii=False, indent=1))
print()
plan = r.get("plan")
print("plan type:", type(plan).__name__)
if isinstance(plan, dict):
    k = list(plan.keys())
    print("plan keys:", k[:12])
    if k:
        print(json.dumps({k[0]: plan[k[0]]}, ensure_ascii=False, indent=1)[:1400])
elif isinstance(plan, list) and plan:
    print(json.dumps(plan[0], ensure_ascii=False, indent=1)[:1400])
