#!/bin/sh
# Set a Terraform variable on the successfulsuccess-gcp workspace (create or
# update): ./gcp/tfvar.sh api_image us-central1-docker.pkg.dev/...@sha256:...
#
# The release (api_image) and the database state (db_activation_policy) live
# in the workspace, not on a command line, so every later run (a plan on a pull
# request, a `make gcp-db-stop`) sees the same values instead of the defaults.
# Uses the token from `terraform login`; it is read here and never printed.
# Only for values that are not secret.
set -eu

KEY=$1
VALUE=$2
ORG=${HCP_ORG:-ooad-anndizhak}
WORKSPACE=${HCP_GCP_WORKSPACE:-successfulsuccess-gcp}
API=https://app.terraform.io/api/v2

TOKEN=$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.terraform.d/credentials.tfrc.json")))["credentials"]["app.terraform.io"]["token"])')
export TOKEN KEY VALUE ORG WORKSPACE API

python3 - <<'EOF'
import json, os, urllib.request

api, token = os.environ["API"], os.environ["TOKEN"]
key, value = os.environ["KEY"], os.environ["VALUE"]
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/vnd.api+json"}

def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(request) as response:
        return json.load(response)

workspace = call("GET", f"{api}/organizations/{os.environ['ORG']}/workspaces/{os.environ['WORKSPACE']}")
ws_id = workspace["data"]["id"]
existing = [v for v in call("GET", f"{api}/workspaces/{ws_id}/vars")["data"]
            if v["attributes"]["key"] == key and v["attributes"]["category"] == "terraform"]
attributes = {"key": key, "value": value, "category": "terraform", "hcl": False, "sensitive": False}
if existing:
    call("PATCH", f"{api}/workspaces/{ws_id}/vars/{existing[0]['id']}",
         {"data": {"type": "vars", "id": existing[0]["id"], "attributes": attributes}})
else:
    call("POST", f"{api}/workspaces/{ws_id}/vars", {"data": {"type": "vars", "attributes": attributes}})
print(f"{os.environ['WORKSPACE']}: {key} = {value}")
EOF
