#!/usr/bin/env bash
# Type-checks every game script with luau-lsp against the Roblox API.
# Used by CI and locally (`./scripts/analyze.sh`). Needs rojo and luau-lsp on PATH
# (`rokit install` provides both). Exits non-zero if any type error is found.
set -euo pipefail

cd "$(dirname "$0")/.."

LUAU_LSP_VERSION="${LUAU_LSP_VERSION:-1.70.1}"
DEFS=".cache/roblox-${LUAU_LSP_VERSION}.d.luau"

# Roblox type definitions published with the matching luau-lsp release
# ("None" = the security level of normal game scripts).
if [[ ! -f "$DEFS" ]]; then
	mkdir -p .cache
	curl -fsSL -o "$DEFS" \
		"https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${LUAU_LSP_VERSION}/scripts/globalTypes.None.d.luau"
fi

rojo sourcemap default.project.json --output sourcemap.json

# Third-party code in Packages is excluded; only our own scripts are checked.
luau-lsp analyze \
	--definitions="$DEFS" \
	--sourcemap=sourcemap.json \
	--no-strict-dm-types \
	--ignore="src/ServerScriptService/Packages/**" \
	src

echo "luau-lsp: no type errors"
