# Self Service Terraform Infrastructure

This repo lets every team get its own **AWS access role** and **S3 buckets** without
asking anyone or writing infrastructure code.

A team writes one small YAML file and opens a pull request. The pipeline shows what will
change, and after merge it creates everything. Each team only ever touches its own files,
its own buckets and its own state.

```yaml
# teams/payments/dev.yaml
schema_version: 1

owner:
  github_team: my-org/payments
  contact: "#payments-eng"
  cost_center: "CC-1042"

workload:                 # the Kubernetes app that may use the team's role
  namespace: payments
  service_account: payments-api

buckets:
  - name: invoices
    visibility: private
  - name: web-assets
    visibility: public
    public:
      mode: cloudfront
      justification: "Images for the checkout page"
```

That file gives the payments team, in the dev environment:

- a role that their app (`payments-api` in the `payments` namespace) uses automatically.
  No passwords or keys are involved.
- two buckets: `dev-payments-invoices` (private) and `dev-payments-web-assets` (public
  through CloudFront).

There is one file per environment: `dev.yaml`, `staging.yaml`, `prod.yaml`.

---

## How it works

1. A team edits `teams/<team>/<env>.yaml` and opens a pull request.
2. CI checks the file and posts a comment saying what will be created, changed or deleted.
3. After merge, **dev** and **staging** are updated automatically. **Prod** waits for one
   approval from the platform team.

Behind the scenes, the same OpenTofu code runs once per team and environment, and each
of those runs keeps its own state file. Teams never block or break each other.

---

## Flows

### Add a new team

1. Create `teams/<team>/dev.yaml`. Copying `teams/payments/dev.yaml` is the easiest
   start. Add `staging.yaml` and `prod.yaml` when you need those environments.
2. Fill in `owner`, `workload` and `buckets`. The namespace must be your team name, or
   start with `<team>-`.
3. Open a pull request, read the comment, and merge.

### Add a bucket

Add an entry under `buckets:` and open a pull request.

Every bucket must say `visibility: private` or `visibility: public`. There is no default,
so nothing becomes public by accident.

### Make a bucket public

```yaml
  - name: web-assets
    visibility: public
    public:
      mode: cloudfront        # recommended: served through CloudFront
      justification: "Why this must be public"
```

`mode: direct` makes the bucket readable straight from S3. In prod this needs an approval
from the platform team.

### Delete a bucket (two pull requests)

1. Mark it with `lifecycle: decommission` and merge. The bucket becomes private and
   your role loses access, but **no data is deleted**.
2. Later, remove the entry and merge.
   - If the bucket is empty, it is deleted.
   - If it still has data, it is kept and handed over to the platform team.

Skipping step 1 is blocked by CI.

### Remove a team

The same two steps, for the whole file:

1. Add `lifecycle: decommission` at the top level of the file and merge.
2. Delete the file and merge.

### Change the platform itself

Changes to `modules/`, `stacks/`, `envs/` or `policy/` affect **every** team. The PR
comment lists all of them, so you can see the full impact before merging.

---

## Run it locally

You don't need an AWS account. A local AWS emulator ([MiniStack](https://github.com/ministackorg/ministack))
runs in a kind cluster.

**1. Install the tools.** Versions are pinned in `mise.toml`.

```sh
mise install
```

**2. Run the fast tests.** These take a few seconds and need nothing running.

```sh
make test validate                 # OpenTofu tests with a fake AWS
conftest verify --policy policy    # safety rules for plans
make ci-test                       # the pull request checks
```

**3. Run the full end-to-end test** against the emulator.

```sh
make ministack-up        # start MiniStack in your kind cluster
make ministack-forward   # keep this running in its own terminal
make e2e                 # about 2 minutes
```

The end-to-end test runs 11 real scenarios: onboarding two teams, adding a bucket, making
a bucket public and private again, locking, deleting buckets safely, removing a team, and
more. Logs go to `.out/e2e/logs/`.

The kind cluster defaults to the `kind-adam` context. Use another one with
`make ministack-up KIND_CONTEXT=kind-<name>`.

---

## What's in the repo

| Folder | What it is |
|---|---|
| `teams/` | The team files. This is the only place teams edit. |
| `schema/` | The rules for team files. Editors use it for autocomplete. |
| `modules/` | Building blocks: a secure bucket, and a team role. |
| `stacks/team/` | The code that turns one team file into real resources. |
| `envs/` | Settings per environment: account, region, cluster. |
| `bootstrap/` | One-time setup per AWS account, done by the platform team. |
| `policy/` | Safety rules every plan must pass. |
| `scripts/` | `tf.sh` runs one team; `ci/` holds the pipeline steps. |
| `.github/` | The CI/CD workflows. |
| `tests/` | Pull request check tests, end-to-end tests, a real-AWS test. |
| `deploy/ministack/` | The local AWS emulator. |


