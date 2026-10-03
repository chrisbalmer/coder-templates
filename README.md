# coder-templates

[Coder](https://coder.com) workspace templates. CI lints every pull request, and pushes a
template version to a Coder deployment on each `<template>-vX.Y.Z` tag. The workspace images
come from [coder-images](https://github.com/chrisbalmer/coder-images).

## Templates

| Template | Display name | Status |
|---|---|---|
| [`k8s-stack`](templates/k8s-stack/README.md) | Linux Stack on Kubernetes | Linux container workspaces, one namespace each, with presets and throwaway lab databases |
| `kali-desktop`, `ubuntu-desktop` | — | Planned: desktop (GUI) workspaces on the existing desktop images |
| macOS (Tart/Orchard) | — | Planned |

Template descriptions are how Coder AI picks a template, so each one says what
the template is **not** for, as well as what it is for.

Each template's `README.md` is its **Docs** tab in Coder, so write it for the
people using the template.

`k8s-stack` gives every workspace its own namespace, `coder-<owner>-<workspace>`, which the
cluster stamps with a quota, LimitRange, NetworkPolicy, Pod Security labels and RoleBindings (a
Capsule tenant in the reference setup). The pod runs with user namespaces (`hostUsers: false`),
uid 1000, seccomp `RuntimeDefault`, and `NET_RAW`/`MKNOD` dropped. Sudo works: workspace
namespaces enforce Pod Security `baseline`, not `restricted`. What a cluster needs for it is in
[`templates/k8s-stack/REQUIREMENTS.md`](templates/k8s-stack/REQUIREMENTS.md).

### Template names

Don't name a template after a sub-page of Coder's template UI: `docs`,
`files`, `resources`, `versions`, `embed`, `insights`, `settings`,
`workspace` or `prebuilds`. Coder 2.37 still routes `/templates/<template>/<page>`
without an organization, so `/templates/coder/workspace` is read as template
`coder`, page `workspace`, and the template page fails with "Resource not
found". That's why this template isn't called `workspace`.

## Releasing

Each template is released on its own, by a tag named `<template>-vX.Y.Z`. The version shows up
in Coder as `vX.Y.Z`.

Pushing a template needs a runner that can reach your Coder deployment, which GitHub's hosted
runners usually can't. So the `release` job runs only where the repository variable
**`CODER_URL`** is set. On GitHub it isn't: tags are linted, and nothing is pushed. To release,
mirror this repository to a forge inside your network (Forgejo and Gitea Actions run
`.github/workflows/` when the repository has no `.forgejo/` or `.gitea/` directory), configure
it there, and push `main` and tags to both.

| Setting on the releasing forge | Kind | Value |
|---|---|---|
| `CODER_URL` | variable | Your deployment, e.g. `https://coder.example.com` |
| `CODER_SESSION_TOKEN` | secret | A token for a template-admin user (a Premium service account works well) |
| `CODER_TEMPLATE_VARIABLES` | variable, optional | YAML keyed by template name, e.g. `k8s-stack: {storage_class_options: [fast, slow]}`. Lists and maps are passed as JSON strings. |

Coder doesn't keep template variable values between pushes, so CI passes
`CODER_TEMPLATE_VARIABLES` with `--variables-file` on every push. The `coder` CLI is downloaded
from your deployment, so it always matches the server.

1. Merge the change to `main`. CI lints **every** template: `terraform fmt`, `validate`,
   `tflint`, the `template.yaml` checks, and that every icon path exists in Coder (on your
   deployment when `CODER_URL` is set, otherwise in Coder's source at `CODER_VERSION`).
2. Tag a release candidate with an **annotated** tag, whose message is what users see in Coder's
   "Update workspace?" dialog (a lightweight tag falls back to the commit subject):
   `git tag -a k8s-stack-v2.1.0-rc.1 -m "Adds the Gitea MCP server" && git push forge k8s-stack-v2.1.0-rc.1`.
   CI pushes `templates/k8s-stack` as an **inactive** version `v2.1.0-rc.1`.
3. Test it by creating a workspace on that version (or promote it), then tag the release
   (`k8s-stack-v2.1.0`). CI pushes it, activates it, and applies the metadata from
   `templates/k8s-stack/template.yaml`.

Release candidates (`-rc.N`) are pushed with `--activate=false` and leave the template's
metadata alone, because it applies to the whole template rather than one version. The exception
is a push that creates the template: Coder makes a new template's first version active, rc or
not, and CI applies the metadata. Pushes don't pass `--provisioner-tag`, so Coder reuses the
active version's provisioner tags, and a new template gets none.

### Adding a template

Create `templates/<name>/` with the Terraform, a `template.yaml` whose `name` equals the
directory name, a `README.md` (the Docs tab, for users) and a `REQUIREMENTS.md` (what the
cluster needs, for admins). CI enforces all four, and rejects names that are Coder
template-page names (see above). The first `<name>-vX.Y.Z` tag creates the template in Coder.

## Local checks

```bash
terraform fmt -check -recursive
cd templates/k8s-stack
terraform init -backend=false
terraform validate
tflint --config ../../.tflint.hcl
```

CI pins Terraform 1.15.5, the version Coder 2.37.3's provisioner ships. When adding a
provider, refresh the lock file for both platforms:
`terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.
