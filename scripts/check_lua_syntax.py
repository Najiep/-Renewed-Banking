from __future__ import annotations
from pathlib import Path
import ctypes
import sys

root = Path(__file__).resolve().parents[1]
lib = ctypes.CDLL('/lib/x86_64-linux-gnu/liblua5.4.so.0')
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lib.luaL_loadfilex.restype = ctypes.c_int
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]

failed: list[str] = []
for path in sorted(root.rglob('*.lua')):
    state = lib.luaL_newstate()
    result = lib.luaL_loadfilex(state, str(path).encode(), None)
    if result:
        message = lib.lua_tolstring(state, -1, None)
        failed.append(f'{path.relative_to(root)}: {(message or b"unknown").decode(errors="replace")}')
    lib.lua_close(state)

if failed:
    print('\n'.join(failed), file=sys.stderr)
    raise SystemExit(1)
print('Lua syntax checks passed.')
