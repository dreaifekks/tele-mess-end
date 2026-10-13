# Sourced by build_and_run.sh and package_macos.sh.
#
# Resolves CODESIGN_IDENTITY for the current machine:
#   - a non-empty value is used as given
#   - "-" forces ad-hoc signing
#   - unset picks the first Developer ID Application identity in the keychain
#     search list, so local builds keep one stable signing identity and
#     Keychain items survive rebuilds
#
# Leaves CODESIGN_IDENTITY empty when the build should be ad-hoc signed and
# sets CODESIGN_IDENTITY_NAME to a printable description.

resolve_codesign_identity() {
  CODESIGN_IDENTITY_NAME="ad-hoc"

  if [[ "${CODESIGN_IDENTITY-}" == "-" ]]; then
    CODESIGN_IDENTITY=""
    return
  fi

  if [[ -n "${CODESIGN_IDENTITY-}" ]]; then
    CODESIGN_IDENTITY_NAME="$CODESIGN_IDENTITY"
    return
  fi

  local line
  line="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep '"Developer ID Application: ' \
    | /usr/bin/head -n 1 || true)"

  if [[ -z "$line" ]]; then
    CODESIGN_IDENTITY=""
    return
  fi

  # Sign by SHA-1 so two certificates with the same name are not ambiguous.
  CODESIGN_IDENTITY="$(/usr/bin/awk '{print $2}' <<<"$line")"
  CODESIGN_IDENTITY_NAME="$(/usr/bin/sed -E 's/^[^"]*"(.*)"$/\1/' <<<"$line")"
}
