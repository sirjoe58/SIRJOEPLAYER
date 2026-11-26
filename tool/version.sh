#!/usr/bin/env bash
# Ricava la versione dal tag (es. v1.0.3 -> 1.0.3) oppure dal pubspec.
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  echo "${GITHUB_REF_NAME#v}"
else
  grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//'
fi
