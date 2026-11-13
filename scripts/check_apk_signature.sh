#!/usr/bin/env bash
# Checks the signature of an APK with apksigner and writes it into the job
# summary (release workflow, specs/RELEASE.md).
#
#   scripts/check_apk_signature.sh <apk>
#
# Environment:
#   UPLOAD_KEY=true        the upload key (ANDROID_KEYSTORE) is set: a debug
#                          signature (CN=Android Debug) fails the check
#   GITHUB_STEP_SUMMARY    file of the job summary (else only the log)
#   APKSIGNER_OUTPUT       file with apksigner's output instead of running
#                          it (tests)
#
# apksigner verify --verbose --print-certs (ApkSignerTool.printCertificate)
# prints per signer "<name> certificate DN: <dn>" and "<name> certificate
# SHA-256 digest: <hex>" – <name> is "Signer #<n>", with v3.1 "Signer
# (minSdkVersion=…, maxSdkVersion=…)", or "Source Stamp Signer"; the digest
# is lower-case hex without separators.
set -euo pipefail

APK="${1:?usage: $0 <apk>}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [[ -n "${APKSIGNER_OUTPUT:-}" ]]; then
  out="$(cat "$APKSIGNER_OUTPUT")"
  tools="(output file)"
else
  tools_dir="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
  tools="build-tools $(basename "$tools_dir")"
  out="$("$tools_dir/apksigner" verify --verbose --print-certs "$APK")"
fi
out="${out//$'\r'/}"
echo "$out"

# keytool format of a hex digest: upper case, pairs separated by ":"
keytool_format() {
  local hex result="" i
  hex="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  for ((i = 0; i < ${#hex}; i += 2)); do
    result+="${result:+:}${hex:i:2}"
  done
  printf '%s' "$result"
}

# the signers in output order: name, DN, SHA-256 (count n; loops over the
# count – an empty array fails "${a[@]}" under set -u in bash 3.2)
names=()
dns=()
digests=()
n=0
# sets idx to the signer [name] (added when new) – no subshell, the
# arrays must keep their entries
idx=0
select_signer() {
  local i
  for ((i = 0; i < n; i++)); do
    if [[ "${names[$i]}" == "$1" ]]; then
      idx=$i
      return
    fi
  done
  names[n]="$1"
  dns[n]=""
  digests[n]=""
  idx=$n
  n=$((n + 1))
}
while IFS= read -r line; do
  if [[ "$line" == *" certificate DN: "* ]]; then
    select_signer "${line%% certificate DN: *}"
    dns[idx]="${line#* certificate DN: }"
  elif [[ "$line" == *" certificate SHA-256 digest: "* ]]; then
    select_signer "${line%% certificate SHA-256 digest: *}"
    digests[idx]="${line#* certificate SHA-256 digest: }"
  fi
done <<<"$out"

failed=""
debug=""
{
  echo "### Android: signature ($tools)"
  echo '```'
  grep -E '^Verified using v' <<<"$out" || true
  for ((i = 0; i < n; i++)); do
    echo "${names[$i]}"
    echo "  Owner (DN): ${dns[$i]}"
    echo "  SHA-256:    ${digests[$i]}"
    echo "  keytool:    $(keytool_format "${digests[$i]}")"
  done
  echo '```'
} >>"$SUMMARY"

if [[ $n -eq 0 ]]; then
  echo "::error::apksigner printed no signer certificate (DN / SHA-256 digest)"
  failed=1
fi
for ((i = 0; i < n; i++)); do
  if [[ -z "${dns[$i]}" || ! "${digests[$i]}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "::error::${names[$i]}: DN or SHA-256 digest missing in the apksigner output"
    failed=1
  fi
  [[ "${dns[$i]}" == *"CN=Android Debug"* ]] && debug=1
done
if [[ -n "$debug" ]]; then
  echo "**Debug key** – no upload key (ANDROID_KEYSTORE) set." >>"$SUMMARY"
  if [[ "${UPLOAD_KEY:-}" == "true" ]]; then
    echo "::error::ANDROID_KEYSTORE is set, but the APK is signed with the debug key"
    failed=1
  fi
fi
[[ -z "$failed" ]]
