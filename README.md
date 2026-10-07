# coder-templates

[Coder](https://coder.com) workspace templates. CI lints every pull request, and pushes a
template version to a Coder deployment on each `<template>-vX.Y.Z` tag. The workspace images
come from [coder-images](https://github.com/chrisbalmer/coder-images).

## Templates

| Template | Display name | Status |
|---|---|---|
| [`k8s-stack`](templates/k8s-stack/README.md) | Linux Stack on Kubernetes | Linux container workspaces, one namespace each, with presets and throwaway lab databases |
| [`k8s-desktop`](templates/k8s-desktop/README.md) | Linux Desktop on Kubernetes | Browser desktops (Xfce over KasmVNC) on the same platform, with Ubuntu and Kali security-lab presets |
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

### Shared modules

Terraform modules that more than one template can use live in [`modules/`](modules/), for
example [`agent-content`](modules/agent-content/README.md), which installs agent skills and
Claude Code plugins from git repositories, and [`herdr`](modules/herdr/README.md), which installs
a pinned [herdr](https://herdr.dev) with its agent integrations. A template uses one as `source = "./modules/<name>"`. Coder uploads only the
template's own directory, without symlinks or hidden files, so `scripts/vendor-modules.sh`
copies `modules/` into every `templates/<name>/modules/` (gitignored). CI runs it before linting
and before every push; run it yourself before local checks.

Other repositories can use a module straight from git, at a module tag
(`modules/<name>/vX.Y.Z`; these don't match the `*-v*` release trigger):
`source = "git::https://github.com/chrisbalmer/coder-templates.git//modules/<name>?ref=modules/<name>/vX.Y.Z"`.
A module with a `tests/` directory has `terraform test` tests, which CI runs.

Backing up workspace homes, with example Kasten K10 policies and a restore procedure, is covered in
[`docs/backups/`](docs/backups/README.md).

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

1. Merge the change to `main`. CI lints **every** template and shared module: `terraform fmt`,
   `validate`, `tflint`, the `template.yaml` checks, and that every icon path exists in Coder (on your
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

### template.yaml

| Field | Applied as | Rule |
|---|---|---|
| `name` | the template's name | Equals the directory name; not a template-page name |
| `display_name` | `--display-name` | Required |
| `description` | `--description` | Required, under 128 bytes. Coder AI picks a template by it |
| `icon` | `--icon` | A path Coder serves, such as `/icon/k8s.png` |
| `default_ttl` | `--default-ttl` | Go duration, more than zero (`8h`). Coder's "Default autostop": new workspaces stop this long after they start |
| `activity_bump` | `--activity-bump` | Go duration (`1h`). Activity pushes the stop time back to at least this far away |

CI applies them with `coder templates edit` on a final release, or on the push that creates the
template. Settings not listed (autostop requirement, autostart, dormancy, failure cleanup,
whether users may change their own schedule) aren't passed, so `coder templates edit` keeps
whatever is set in Coder. A new `default_ttl` applies to workspaces created after it; while users
may set their own schedule, an existing workspace keeps the one it has.

## Local checks

```bash
./scripts/vendor-modules.sh
terraform fmt -check -recursive
cd templates/k8s-stack
terraform init -backend=false
terraform validate
tflint --config ../../.tflint.hcl
```

CI pins Terraform 1.16.2, the version Coder 2.38.0's provisioner ships. When adding a
provider, refresh the lock file for both platforms:
`terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`.
