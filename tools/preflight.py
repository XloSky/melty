#!/usr/bin/env python3
"""Preflight: lay every sheet's rows and columns over each other.

Blocking (exit 1): unfilled cells, wrong types, enum values outside the column's list,
references to rows that do not exist, and rows nothing uses.
Reported but not blocking: cells whose status says they still need checking in the real game,
and sim tests that have not passed yet (--strict makes those blocking too).
"""
import json
import sys
from pathlib import Path

SHEETS = Path(__file__).resolve().parent.parent / "design" / "sheets"


def load():
    sheets = {}
    for path in sorted(SHEETS.glob("*.json")):
        data = json.loads(path.read_text())
        sheets[data["sheet"]] = data
    return sheets


def empty(value):
    return value is None or value == "" or value == []


def check(sheets):
    blocking, pending = [], []
    ids = {name: {row["id"] for row in s["rows"]} for name, s in sheets.items()}
    used = {name: set() for name in sheets}

    for name, sheet in sheets.items():
        seen = set()
        for row in sheet["rows"]:
            rid = row.get("id", "?")
            where = f"{name}.{rid}"
            if rid in seen:
                blocking.append(f"{where}: duplicate id")
            seen.add(rid)
            for extra in set(row) - set(sheet["columns"]):
                blocking.append(f"{where}.{extra}: column not declared in the sheet")
            for col, spec in sheet["columns"].items():
                cell = f"{where}.{col}"
                if col not in row:
                    blocking.append(f"{cell}: missing")
                    continue
                value = row[col]
                kind = spec["type"]
                if value is None and spec.get("nullable"):
                    continue
                if empty(value) and not (spec.get("optional_empty") and value == []):
                    blocking.append(f"{cell}: unfilled")
                    continue
                if kind == "number" and not isinstance(value, (int, float)):
                    blocking.append(f"{cell}: expected a number, got {value!r}")
                elif kind == "bool" and not isinstance(value, bool):
                    blocking.append(f"{cell}: expected true/false, got {value!r}")
                elif kind in ("list", "ref_list") and not isinstance(value, list):
                    blocking.append(f"{cell}: expected a list, got {value!r}")
                elif kind == "enum" and value not in spec["values"]:
                    blocking.append(f"{cell}: {value!r} is not one of {spec['values']}")
                if kind in ("ref", "ref_list"):
                    target = spec["sheet"]
                    if target not in ids:
                        blocking.append(f"{cell}: refers to missing sheet {target!r}")
                        continue
                    for ref in value if isinstance(value, list) else [value]:
                        if ref not in ids[target]:
                            blocking.append(f"{cell}: {ref!r} is not a row of {target}")
                        else:
                            used[target].add(ref)
                if col == "status" and value != "in-game-verified":
                    pending.append(f"{cell}: {value}")
                if col == "in_game" and value != "verified":
                    pending.append(f"{cell}: {value}")
                if name == "tests" and col == "result" and value != "pass":
                    pending.append(f"{cell}: {value}")

        # Tuning ranges must contain their value.
        if name == "tuning":
            for row in sheet["rows"]:
                if all(isinstance(row.get(k), (int, float)) for k in ("value", "min", "max")):
                    if not row["min"] <= row["value"] <= row["max"]:
                        blocking.append(f"tuning.{row['id']}: value {row['value']} outside [{row['min']}, {row['max']}]")

    # Every row must be reachable from something that uses it (tests and abilities are roots).
    for name in ("tuning", "hooks", "inputs", "visuals"):
        for rid in sorted(ids.get(name, set()) - used[name]):
            if name == "hooks" and rid in ROOT_HOOKS:
                continue
            if name == "inputs" and rid in MODIFIER_ONLY_INPUTS & used["inputs"]:
                continue
            blocking.append(f"{name}.{rid}: nothing uses this row")
    for rid in sorted(ids.get("abilities", set()) - used["abilities"]):
        blocking.append(f"abilities.{rid}: no test covers this ability")
    return blocking, pending


# Hooks the mod shell uses regardless of ability (init, settings, overlay, fallbacks).
ROOT_HOOKS = {"on_init", "overlay_events", "register_input", "settings_io", "raycast_alt"}
MODIFIER_ONLY_INPUTS = {"aim_state"}


def main():
    strict = "--strict" in sys.argv
    sheets = load()
    blocking, pending = check(sheets)
    total = sum(len(s["rows"]) * len(s["columns"]) for s in sheets.values())
    print(f"preflight: {len(sheets)} sheets, {sum(len(s['rows']) for s in sheets.values())} rows, {total} cells")
    for line in blocking:
        print("  BLOCKING", line)
    for line in pending:
        print("  PENDING ", line)
    print(f"preflight: {len(blocking)} blocking, {len(pending)} pending")
    if blocking or (strict and pending):
        sys.exit(1)


if __name__ == "__main__":
    main()
