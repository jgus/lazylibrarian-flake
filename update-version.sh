#!/usr/bin/env -S nix shell nixpkgs#bash nixpkgs#curl nixpkgs#jq nixpkgs#nix-prefetch-git nixpkgs#gnused --command bash

# Bumps pin.nix to the requested commit of LazyLibrarian/LazyLibrarian (GitLab) and re-pins the sibling flake inputs (slskd-api, iso639-lang) in flake.nix to the exact-version branches matching upstream's uv-compiled requirements.txt. Run from the flake root:
#
#   nix run .#update-version              # latest commit on master
#   nix run .#update-version -- <rev>     # specific commit
#
# Always re-validates everything; idempotent on no-change runs.

set -euo pipefail

FLAKE_ROOT="${FLAKE_ROOT:-${PWD}}"
pin="${FLAKE_ROOT}/pin.nix"
flake="${FLAKE_ROOT}/flake.nix"

repo_owner=LazyLibrarian
repo_name=LazyLibrarian
project="${repo_owner}%2F${repo_name}"

if [[ ! -f "${pin}" ]]; then
  echo "error: no pin.nix in ${FLAKE_ROOT}" >&2
  exit 1
fi

if [[ $# -ge 1 && -n "${1}" ]]; then
  ref="${1}"
  echo "Resolving requested ref ${ref}..."
  commit=$(curl -sSfL "https://gitlab.com/api/v4/projects/${project}/repository/commits/${ref}")
else
  echo "Querying GitLab for latest master commit..."
  commit=$(curl -sSfL "https://gitlab.com/api/v4/projects/${project}/repository/branches/master" | jq -r '.commit')
fi
new_rev=$(jq -r '.id' <<<"${commit}")
new_date=$(jq -r '.committed_date' <<<"${commit}" | cut -d'T' -f1)
new_version="0-unstable-${new_date}"

cur_version=$(nix eval --raw --file "${pin}" version 2>/dev/null || echo "")
cur_rev=$(nix eval --raw --file "${pin}" sourceRev 2>/dev/null || echo "")
cur_hash=$(nix eval --raw --file "${pin}" sourceHash 2>/dev/null || echo "")

echo "  current: ${cur_version} (${cur_rev:-<empty>})"
echo "  target:  ${new_version} (${new_rev})"

# Always prefetch — gives us source path for requirements.txt parsing and validates the hash.
echo "Computing source hash..."
prefetch=$(nix-prefetch-git --quiet --url "https://gitlab.com/${repo_owner}/${repo_name}.git" --rev "${new_rev}")
new_source_hash=$(jq -r '.hash' <<<"${prefetch}")
src_path=$(jq -r '.path' <<<"${prefetch}")

if [[ "${cur_version}" != "${new_version}" || "${cur_rev}" != "${new_rev}" || "${cur_hash}" != "${new_source_hash}" ]]; then
  echo "Writing pin.nix..."
  cat > "${pin}" <<EOF
# Auto-managed by \`nix run .#update-version\`. Manual edits will be overwritten by the next bump.
{
  version = "${new_version}";
  sourceRev = "${new_rev}";
  sourceHash = "${new_source_hash}";
}
EOF
fi

# --- Propagate sibling versions from upstream requirements.txt (uv-compiled, exact ==) ---
req_file="${src_path}/requirements.txt"
if [[ ! -f "${req_file}" ]]; then
  echo "warning: no requirements.txt at ${req_file}; sibling URLs unchanged." >&2
else
  slskd_api_version=$(sed -nE 's/^slskd-api==([^ ;[:space:]]+).*/\1/p' "${req_file}" | head -1)
  iso639_lang_version=$(sed -nE 's/^iso639-lang==([^ ;[:space:]]+).*/\1/p' "${req_file}" | head -1)

  echo "  upstream pins: slskd-api==${slskd_api_version:-<unknown>}, iso639-lang==${iso639_lang_version:-<unknown>}"

  if [[ -n "${slskd_api_version}" ]]; then
    echo "  pinning slskd-api to v${slskd_api_version} (exact branch)"
    sed -i -E "s|(url = \"github:jgus/slskd-api-flake)(/[^\"]*)?(\")|\\1/v${slskd_api_version}\\3|" "${flake}"
  fi
  if [[ -n "${iso639_lang_version}" ]]; then
    echo "  pinning iso639-lang to v${iso639_lang_version} (exact branch)"
    sed -i -E "s|(url = \"github:jgus/iso639-lang-flake)(/[^\"]*)?(\")|\\1/v${iso639_lang_version}\\3|" "${flake}"
  fi
fi

echo "Verifying lazylibrarian build..."
nix build --option post-build-hook "" "${FLAKE_ROOT}#lazylibrarian" --no-link

echo
echo "Updated to ${new_version} (${new_rev})"
echo "  Commit pin.nix / flake.nix / flake.lock to capture."
