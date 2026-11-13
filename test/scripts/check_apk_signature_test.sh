#!/usr/bin/env bash
# Tests of scripts/check_apk_signature.sh with apksigner output in the
# format of ApkSignerTool (verify --verbose --print-certs):
#   bash test/scripts/check_apk_signature_test.sh
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
SCRIPT=scripts/check_apk_signature.sh
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

D1=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
D2=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
K1=01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF

header() {
  cat <<OUT
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Verified using v3.1 scheme (APK Signature Scheme v3.1): ${1:-false}
Verified using v4 scheme (APK Signature Scheme v4): false
Verified for SourceStamp: false
Number of signers: ${2:-1}
OUT
}
signer() { # name dn digest
  cat <<OUT
$1 certificate DN: $2
$1 certificate SHA-256 digest: $3
$1 certificate SHA-1 digest: 0123456789abcdef0123456789abcdef01234567
$1 certificate MD5 digest: 0123456789abcdef0123456789abcdef
$1 key algorithm: RSA
$1 key size (bits): 2048
$1 public key SHA-256 digest: $D2
$1 public key SHA-1 digest: 0123456789abcdef0123456789abcdef01234567
$1 public key MD5 digest: 0123456789abcdef0123456789abcdef
OUT
}

# run <name> <expected exit 0|1> <upload key> <summary/log must contain…>
# (an argument "!text": must NOT contain text)
run() {
  local name="$1" expect="$2" upload="$3"
  shift 3
  : >"$WORK/summary"
  APKSIGNER_OUTPUT="$WORK/out" GITHUB_STEP_SUMMARY="$WORK/summary" \
    UPLOAD_KEY="$upload" bash "$SCRIPT" app.apk >"$WORK/log" 2>&1
  local code=$?
  local ok=1
  if [[ "$expect" == 0 && $code -ne 0 ]] || [[ "$expect" == 1 && $code -eq 0 ]]; then
    ok=0
    echo "  exit $code, expected $expect"
  fi
  local want
  for want in "$@"; do
    if [[ "$want" == '!'* ]]; then
      if grep -qF -- "${want:1}" "$WORK/summary" "$WORK/log"; then
        ok=0
        echo "  must not contain: ${want:1}"
      fi
    elif ! grep -qF -- "$want" "$WORK/summary" "$WORK/log"; then
      ok=0
      echo "  missing: $want"
    fi
  done
  if [[ $ok -eq 1 ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    sed 's/^/     | /' "$WORK/summary"
    fails=$((fails + 1))
  fi
}

{ header; signer "Signer #1" "C=US, O=Android, CN=Android Debug" "$D1"; } >"$WORK/out"
run "debug key, no upload key: passes with a note" 0 false \
  "Key:        debug key (C=US, O=Android, CN=Android Debug)" "SHA-256:    $D1" \
  "keytool:    $K1" "**Debug key**" "Verified using v2 scheme (APK Signature Scheme v2): true"
run "debug key although the upload key is set: fails" 1 true \
  "ANDROID_KEYSTORE is set, but the APK is signed with the debug key"

{ header false 2
  signer "Signer #1" "CN=Jan Kramer, O=jankstar, C=DE" "$D1"
  signer "Signer #2" "CN=Second, O=jankstar, C=DE" "$D2"; } >"$WORK/out"
run "upload key, two signers: both listed, no owner name" 0 true \
  "Signer #1" "Key:        upload key (owner not shown)" \
  "Signer #2" "SHA-256:    $D2" "Signer #1 certificate DN: (hidden)" \
  "!Jan Kramer" "!CN=Second"

{ header true
  signer "Signer (minSdkVersion=33, maxSdkVersion=2147483647)" "CN=Rotated, C=DE" "$D2"
  signer "Signer (minSdkVersion=24, maxSdkVersion=32)" "CN=Jan Kramer, C=DE" "$D1"
  signer "Source Stamp Signer" "CN=Stamp, C=DE" "$D1"; } >"$WORK/out"
run "v3.1 signer names and source stamp" 0 true \
  "Signer (minSdkVersion=33, maxSdkVersion=2147483647)" \
  "Signer (minSdkVersion=24, maxSdkVersion=32)" "Source Stamp Signer" \
  "!CN=Rotated" "!Jan Kramer"

{ header; echo "Signer #1 certificate DN: CN=Jan Kramer, C=DE"; } >"$WORK/out"
run "digest missing: fails" 1 false "DN or SHA-256 digest missing" "!Jan Kramer"

header >"$WORK/out"
run "no signer printed: fails" 1 false "printed no signer certificate"

{ header; signer "Signer #1" "CN=Jan Kramer, C=DE" "$D1"; } | sed 's/$/\r/' >"$WORK/out"
run "CRLF line ends" 0 true "Key:        upload key (owner not shown)" \
  "keytool:    $K1" "!Jan Kramer"

if [[ $fails -ne 0 ]]; then
  echo "$fails failed"
  exit 1
fi
echo "all passed"
