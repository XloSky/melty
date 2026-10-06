#!/usr/bin/env python3
"""Run every row of design/sheets/tests.json in the LuaJIT simulator and record the result in the sheet.

Uses LuaJIT 2.1 through lupa (pip install lupa), the same Lua that Cyber Engine Tweaks embeds.
--no-write leaves the sheet untouched.
"""
import json
import os
import sys
from pathlib import Path

from lupa import luajit21

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod" / "web_of_night_city"
SHEET = ROOT / "design" / "sheets" / "tests.json"


def main():
    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    os.chdir(MOD)  # CET resolves require("modules/x") from the mod folder
    lua.execute(f'package.path = "{ROOT / "tests" / "sim"}/?.lua;" .. package.path')
    harness = lua.eval('require("harness")')
    harness.load(str(MOD))
    scenarios = lua.eval('require("scenarios")')

    sheet = json.loads(SHEET.read_text())
    failed = 0
    for row in sheet["rows"]:
        fn = scenarios[row["id"]]
        if fn is None:
            print(f"MISSING {row['id']}: no scenario function")
            row["result"] = "fail"
            failed += 1
            continue
        ok, details = fn()
        row["result"] = "pass" if ok else "fail"
        failed += 0 if ok else 1
        print(f"{'PASS' if ok else 'FAIL'} {row['id']}: {details}")

    if "--no-write" not in sys.argv:
        SHEET.write_text(json.dumps(sheet, indent=2) + "\n")
    print(f"sim: {len(sheet['rows']) - failed}/{len(sheet['rows'])} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
