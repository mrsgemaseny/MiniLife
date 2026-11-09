from pathlib import Path
import difflib
p=Path('scripts/core/debug_console.gd')
old=p.read_text(encoding='utf-8-sig')
new=old.replace('assert(', '_check(')
new=new.replace('func _ready() -> void:', 'var _test_failures: int = 0\n\nfunc _check(condition: bool, message: String = "Failed check") -> void:\n\tif not condition:\n\t\t_test_failures += 1\n\t\tprinterr("E2E_FAILURE: ", message)\n\nfunc _ready() -> void:',1)
new=new.replace('\tprint("E2E_ALL_SYSTEMS_VERIFIED_OK")','\tif _test_failures > 0:\n\t\tprinterr("E2E_FAILED: ", _test_failures, " failed checks")\n\t\tget_tree().quit(1)\n\t\treturn\n\tprint("E2E_ALL_SYSTEMS_VERIFIED_OK")')
new=new.replace('[E2E_SUITE] ALL 13 PHASES EXHAUSTIVELY VERIFIED (100% OK)', '[E2E_SUITE] 13 PHASES EXECUTED; CHECKING RESULTS')
print('*** Begin Patch\n*** Update File: '+str(p))
print(''.join(list(difflib.unified_diff(old.splitlines(True),new.splitlines(True)))[2:]),end='')
print('*** End Patch')
