# Lab 9: everything created on Google Cloud and HCP Terraform

Kept up to date while the lab is built. After grading, clean up from the bottom
up: `terraform destroy` in `gcp/`, then in `gcp/bootstrap/`, then the project
and the HCP workspace. Nothing here is a secret.

## Outside Terraform (created by hand)

| What | ID / name | Created | How to remove |
| --- | --- | --- | --- |
| GCP project | `spry-anndizhak-2026` (number 293282320220), name "Spry Lab 9" | 2026-11-14, `gcloud projects create` | `gcloud projects delete spry-anndizhak-2026` (the ID can never be reused) |
| Billing link | project → billing account `011B31-E1D51A-E8411F` (Free Trial) | 2026-11-14 | goes with the project |
| HCP Terraform workspace | `ooad-anndizhak/successfulsuccess-gcp` (`ws-Kquo9hS82XrQjNL5`), CLI-driven, Terraform 1.17.0 | 2026-11-14, HCP API | Workspace → Settings → Destruction and Deletion |
| Workspace env vars | `TFC_GCP_PROVIDER_AUTH`, `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL`, `TFC_GCP_WORKLOAD_PROVIDER_NAME` (not sensitive) | 2026-11-14 | go with the workspace |
| Local gcloud settings | `core/project`, ADC quota project = `spry-anndizhak-2026` | 2026-11-14 | `gcloud config unset project` |

Not created by this lab and not to be touched: the projects `successfuls-auth`
(Google OAuth client for Cognito) and `gen-lang-client-0098161883`.

Side effect to remember: on 2026-11-14 at 13:57 UTC Firebase was added to
`successfuls-auth` by mistake in the Firebase console (meant for this project).
Nothing else was changed there. Firebase cannot be removed from a project
without deleting the project, and it costs nothing while unused.

## gcp/bootstrap (local state, run from the laptop)

| Resource | Name |
| --- | --- |
| APIs | cloudresourcemanager, serviceusage, iam, iamcredentials, sts, firebase (`disable_on_destroy = false`) |
| Service account | `terraform@spry-anndizhak-2026.iam.gserviceaccount.com`, no keys |
| Service account | `meetings-api@spry-anndizhak-2026.iam.gserviceaccount.com`, no keys |
| Project roles of `terraform` | run.admin, cloudsql.admin, artifactregistry.admin, secretmanager.admin, serviceusage.serviceUsageAdmin |
| `terraform` → `meetings-api` | iam.serviceAccountUser on that one account |
| Project role of `meetings-api` | cloudsql.client |
| Workload identity pool | `hcp-terraform` |
| OIDC provider | `hcp-terraform/app-terraform-io`, issuer `https://app.terraform.io`, condition on org `org-tFizD3ANLvCs6pT5` and workspace `ws-Kquo9hS82XrQjNL5` |
| `terraform` ← pool | iam.workloadIdentityUser for `attribute.terraform_workspace_id/ws-Kquo9hS82XrQjNL5` |
| Firebase | `google_firebase_project` — Firebase added to the project (Blaze through the Free Trial billing) |

## gcp/ (state in HCP Terraform, workspace successfulsuccess-gcp)

Applied 2026-11-14 (16 resources), then the API image (1 change).

| Resource | Name | Bills |
| --- | --- | --- |
| APIs | run, sqladmin, artifactregistry, secretmanager, firebasehosting, logging (`disable_on_destroy = false`) | — |
| Artifact Registry | `us-central1-docker.pkg.dev/spry-anndizhak-2026/meetings`, keeps the last 3 images | free up to 0.5 GB |
| **Cloud SQL** | `meetings-pg`: Postgres 17, db-f1-micro, 10 GB SSD, zonal, no backups, public IP with no authorized networks, deletion protection | **$0.0105/h while running + $1.70/month disk** |
| Cloud SQL database / user | `meetings` / `app` | — |
| Random password | `random_password.db` (only in the HCP state and in the secret) | — |
| Secret Manager | `database-url` (version 1); `meetings-api` has secretAccessor on it | free (6 versions) |
| Cloud Run | `meetings-api`, https://meetings-api-qookbgnkcq-uc.a.run.app, runs as `meetings-api@`, min 0 / max 2, deletion protection | $0 idle |
| Cloud Run IAM | `allUsers` → run.invoker (public, like the AWS function URL) | — |

Terraform variables on the workspace (set by `gcp/tfvar.sh`, not secret):
`api_image` (the release, pinned by digest).

## Firebase Hosting (Firebase CLI, not Terraform)

| What | Name |
| --- | --- |
| Default site | `spry-anndizhak-2026`, https://spry-anndizhak-2026.web.app (also `.firebaseapp.com`), created by Firebase |
| Release | `make gcp-deploy-frontend` from `gcp/hosting/` (rewrites `/api/**` and `/health` to `meetings-api`) |

Removing: `firebase hosting:disable --project spry-anndizhak-2026`, or with the project.

## Local artefacts

Docker images `meetings-api:gcp-test`, `meetings-lambda:test` and
`…/meetings-api:gcp-*` on the laptop (`docker image rm`); `gcp/hosting/public/`
(git-ignored build output); `gcloud auth configure-docker` added a credential
helper for `us-central1-docker.pkg.dev` to `~/.docker/config.json`.
