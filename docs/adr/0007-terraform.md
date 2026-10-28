# ADR 0007: Infrastructure as code with Terraform and HCP Terraform

- Status: accepted
- Date: 2026-10-28

## Context

Labs 4–6 added three CloudFormation stacks next to the base ones: `auth`
(Cognito sign-in with Google), `reports` (the weekly report: bucket, queue,
schedule, two functions, SES) and `ai` (the agenda parser and the budget alarm).
They worked, but:

- The project already reaches outside AWS: the Google OAuth client, the GitHub
  repository and its CI role. CloudFormation stops at the edge of one AWS
  account.
- The project will need a second environment (staging). With CloudFormation
  that means copying stacks and parameters by hand.
- Each stack was deployed from a laptop with `make deploy-*`, using the
  laptop's AWS keys. Nobody reviewed a plan before a change reached AWS.

The stacks held data that must not be lost: three user accounts in the user
pool and six reports in the bucket.

## Decision

- The three stacks are replaced by Terraform in `infra/` (`auth.tf`,
  `reports.tf`, `ai.tf`), one root module with one HCP Terraform workspace,
  `ooad-anndizhak/successfulsuccess-dev`.
- The existing resources were adopted, not re-created: every resource in the
  three templates got `DeletionPolicy: Retain`, the stacks were deleted, and 41
  `import` blocks handed the resources to Terraform. The first plan was
  `41 to import, 0 to add, 3 to change, 0 to destroy`; the three in-place
  changes were cosmetic (the mailer's code now comes from `mailer/index.py`, and
  two values became marked as sensitive). Nothing was re-created, so the users,
  the reports, the client ID and the parser URL all stayed the same. The plan
  after the migration says `No changes`.
- HCP Terraform keeps the state, locks it during every run and applies after a
  merge to `main`; every pull request gets a plan as a check. Runs assume an AWS
  role through OIDC (`hcp-terraform-ooad-anndizhak`), created once from a
  laptop by a small bootstrap configuration with a local state.
- The base stacks (`ecr`, `backend`, `frontend`, `github`) stay CloudFormation
  for now. Terraform reads the backend stack's outputs with the
  `aws_cloudformation_stack` data source instead of copying them.
- The user pool and the reports bucket have `prevent_destroy`.

## Alternatives considered

- **Keep CloudFormation.** AWS keeps the state and rolls back failed changes on
  its own. Lost because it covers AWS only, and a second environment or the
  Google and GitHub settings would stay outside the code.
- **AWS CDK.** Real programming languages on top of CloudFormation. Lost for
  the same reason: it still produces CloudFormation, AWS only, and it adds a
  build step and a second language to the project.
- **OpenTofu.** The open-source fork with the same files and commands. A good
  choice, and the files would work unchanged. Lost only because the course uses
  HCP Terraform, which runs Terraform; switching later is cheap.
- **Terraform with an S3 backend and runs from GitHub Actions.** Also valid.
  Lost because HCP Terraform gives state, locking, history, plans on pull
  requests and OIDC credentials without more pipeline code.

## Consequences

- **Who can change the infrastructure.** Anyone who can open a pull request
  can propose a change; it reaches AWS only after review and merge, applied by
  HCP Terraform. Nobody needs AWS keys for it. The laptop path
  (`terraform apply` from the CLI) remains for emergencies and is no longer
  part of the workflow; the Makefile has no `apply`.
- **Where the secrets are.** `google_client_secret` and `db_password` are
  sensitive variables in the HCP Terraform workspace, never in Git. They are
  also in the state (HCP Terraform stores it encrypted, readable by whoever has
  state access to the workspace), in the Cognito identity provider, and, for
  the password, in the builder's environment variables, as before.
  `sensitive = true` hides them in plans, not in the state.
- **If HCP Terraform is down.** The running system is not affected: the site,
  the API, sign-in, the reports and the parser keep working. Only
  infrastructure changes wait. In an emergency the state can be downloaded from
  HCP Terraform when it is back, or a run can be done locally with the
  workspace switched to local execution.
- **Two roads.** GitHub Actions deploys the application (the backend image);
  HCP Terraform deploys the infrastructure. When a change needs both (for
  example, a new environment variable the code reads), the infrastructure goes
  first, then the code.
- **New risks.** Terraform stops halfway on a failed change instead of rolling
  back, so a failed apply needs a fix and another apply. The bootstrap role has
  `AdministratorAccess` and trusts every workspace of the organization; it
  should be narrowed to this workspace and the services it manages.
- **Images.** The builder and the parser are pinned by digest in
  `terraform.tfvars`; a new image is a pull request that changes that line
  (`make infra-image` prints it).
