variable "project_id" {
  description = "The Google Cloud project for Lab 9."
  type        = string
  default     = "spry-anndizhak-2026"
}

variable "region" {
  type    = string
  default = "us-central1"
}

# Immutable IDs from HCP Terraform (not secrets): the organization's external ID
# and the workspace ID. Names are not used in the trust condition.
variable "hcp_organization_id" {
  description = "External ID of the ooad-anndizhak organization (org-…)."
  type        = string
  default     = "org-tFizD3ANLvCs6pT5"
}

variable "hcp_workspace_id" {
  description = "ID of the successfulsuccess-gcp workspace (ws-…)."
  type        = string
  default     = "ws-Kquo9hS82XrQjNL5"
}
