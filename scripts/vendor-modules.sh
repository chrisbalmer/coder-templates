#!/usr/bin/env bash
# Copies each shared module in modules/ into every templates/<name>/modules/,
# so templates can use them as source = "./modules/<module>". Coder's template
# upload stores symlinks as links and skips hidden paths, so the copies must be
# real and not hidden. They're gitignored; CI runs this before linting and
# before `coder templates push`. Run it before local checks too.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
for t in "$root"/templates/*/; do
  rm -rf "${t}modules"
  mkdir "${t}modules"
  names=()
  for m in "$root"/modules/*/; do
    m=${m%/}
    cp -R "$m" "${t}modules/"
    rm -rf "${t}modules/${m##*/}/.terraform" "${t}modules/${m##*/}/.terraform.lock.hcl"
    names+=("${m##*/}")
  done
  echo "vendored ${names[*]} into ${t#"$root"/}modules"
done
