# Non-secret values only. google_client_secret and db_password are sensitive
# Terraform variables in the HCP Terraform workspace.

project_name = "successfulsuccess"
region       = "us-east-1"

# auth
domain_prefix    = "successfuls"
callback_urls    = ["https://d327ma3w90nqqi.cloudfront.net/auth/callback/", "http://localhost:3000/auth/callback/"]
logout_urls      = ["https://d327ma3w90nqqi.cloudfront.net/", "http://localhost:3000/"]
google_client_id = "551504844297-fdt2nr8vp6q9vn48q20203eac1r52k4g.apps.googleusercontent.com"

# reports
vpc_id            = "vpc-08162316fcca4051f"
subnet_ids        = ["subnet-04c906b4d2b342420", "subnet-074272ca421bcdfb8", "subnet-03037b283cae3de26", "subnet-0110c73b087460216", "subnet-0a0c933994eccbdf9", "subnet-02f5a430e7111e9a5"]
route_table_ids   = ["rtb-04ed0514169eb78b8"]
security_group_id = "sg-08d97dc10d3adb3ac"
architecture      = "arm64"
builder_image_uri = "347282156909.dkr.ecr.us-east-1.amazonaws.com/successfulsuccess-backend@sha256:0856e2bd8faaecdd14f22b7329e9750ccb1e78358e08393779acf1abfac5350f"
report_email      = "annadizhak8@gmail.com"

# ai
parser_image_uri = "347282156909.dkr.ecr.us-east-1.amazonaws.com/successfulsuccess-backend@sha256:68b16222935d7bf630579d190a77976bf8e340ec8a32bf2dcaca3d4c7022828f"
parser_api       = "converse"
parser_model     = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
allowed_origins  = ["https://d327ma3w90nqqi.cloudfront.net", "http://localhost:3000"]
alert_email      = "annadizhak8@gmail.com"
