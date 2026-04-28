#!/usr/bin/env bash
# 从 hp_repo/PGO_RPMS 下的 *.perf.x86_64.rpm 解压出 runbenchmarks.lua 所需的目录：
#   ./pgo_lua_root   （lua-libs + lua）
#   ./pgo_luajit_root（luajit）
#
# 用法：
#   ./extract_pgo_roots.sh
#   PGO_RPMS=/自定义路径/PGO_RPMS ./extract_pgo_roots.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 默认：<仓库根>/PGO_RPMS（本脚本在 lua_test/Lua-Benchmarks 下）
HP_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PGO_RPMS="${PGO_RPMS:-${HP_REPO_ROOT}/PGO_RPMS}"

LUA_DIR="${PGO_RPMS}/lua"
LJ_DIR="${PGO_RPMS}/luajit"

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "缺少命令: $1" >&2
		exit 1
	}
}

pick_one() {
	local pattern="$1"
	local msg="$2"
	local f
	f=$(compgen -G "$pattern" | head -1 || true)
	if [[ -z "$f" || ! -f "$f" ]]; then
		echo "未找到 $msg: $pattern" >&2
		exit 1
	fi
	printf '%s' "$f"
}

need_cmd rpm2cpio
need_cmd cpio

if [[ ! -d "$LUA_DIR" || ! -d "$LJ_DIR" ]]; then
	echo "PGO_RPMS 路径无效或未包含 lua/luajit 子目录: $PGO_RPMS" >&2
	exit 1
fi

RPM_LUA_LIBS="$(pick_one "${LUA_DIR}/lua-libs-*tl4.perf.x86_64.rpm" 'lua-libs perf rpm')"
RPM_LUA_BIN="$(pick_one "${LUA_DIR}/lua-[0-9]*-*tl4.perf.x86_64.rpm" 'lua perf rpm（非 libs/debug）')"
RPM_LUAJIT="$(pick_one "${LJ_DIR}/luajit-[0-9]*-*tl4.perf.x86_64.rpm" 'luajit perf rpm')"

echo "PGO_RPMS=$PGO_RPMS"
echo "  lua-libs: $RPM_LUA_LIBS"
echo "  lua:      $RPM_LUA_BIN"
echo "  luajit:   $RPM_LUAJIT"
echo

extract_rpm() {
	local dest="$1"
	local rpm="$2"
	mkdir -p "$dest"
	(
		cd "$dest"
		rpm2cpio "$rpm" | cpio -idmv 2>/dev/null
	)
}

rm -rf pgo_lua_root pgo_luajit_root

echo "-> pgo_lua_root/"
extract_rpm "${SCRIPT_DIR}/pgo_lua_root" "$RPM_LUA_LIBS"
extract_rpm "${SCRIPT_DIR}/pgo_lua_root" "$RPM_LUA_BIN"

echo "-> pgo_luajit_root/"
extract_rpm "${SCRIPT_DIR}/pgo_luajit_root" "$RPM_LUAJIT"

echo
echo "完成。请验证:"
echo "  LD_LIBRARY_PATH=${SCRIPT_DIR}/pgo_lua_root/usr/lib64:\\\$LD_LIBRARY_PATH ${SCRIPT_DIR}/pgo_lua_root/usr/bin/lua -v"
echo "  LD_LIBRARY_PATH=${SCRIPT_DIR}/pgo_luajit_root/usr/lib64:\\\$LD_LIBRARY_PATH ${SCRIPT_DIR}/pgo_luajit_root/usr/bin/luajit -v"
