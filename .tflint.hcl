# Bundled ruleset (no source/version): tflint --init downloads nothing, so CI
# needs no Sigstore egress.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
