COMPOSE ?= docker compose
comma := ,

# Local configuration (gitignored). These assignments beat variables exported in
# the shell, so override one on the command line instead: make aws-deploy-backend
# AWS_LAMBDA_ARCH=arm64
-include .env
# Every stack (ECR, Lambda, Aurora, S3 + CloudFront) is created in this one region.
AWS_REGION ?= us-east-1
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION PROJECT_NAME
# Secrets reach recipes as environment variables and are written $$NAME there,
# never $(NAME): a recipe's text is printed by `make -n` and on a shell error,
# and must not contain a secret's value.
export AWS_DB_PASSWORD GOOGLE_CLIENT_SECRET

# The AWS CLI runs in a container so nothing has to be installed on the host.
# The repository is mounted at /aws (the image's workdir) so the CLI can read
# infra/*.yml. Pass AWS=aws to use a CLI installed on the host instead.
AWS ?= docker run --rm \
	-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
	-e AWS_DEFAULT_REGION=$(AWS_REGION) \
	-v $(CURDIR):/aws -w /aws \
	amazon/aws-cli:latest

APP_STACK ?= $(PROJECT_NAME)-backend
ECR_STACK ?= $(PROJECT_NAME)-ecr
FRONTEND_STACK ?= $(PROJECT_NAME)-frontend
GITHUB_STACK ?= $(PROJECT_NAME)-github
AUTH_STACK ?= $(PROJECT_NAME)-auth
REPORTS_STACK ?= $(PROJECT_NAME)-reports
# Every Monday 07:00 in APP_TIMEZONE. A test deploy can pass
# REPORT_SCHEDULE="rate(5 minutes)"; the next plain deploy restores the cron.
REPORT_SCHEDULE ?= cron(0 7 ? * MON *)
# The builder gets an image of its own, built from the working tree, so report
# code can ship before (or without) a backend deploy. The tag names the commit,
# and says when the tree had uncommitted changes.
REPORTS_IMAGE_TAG ?= reports-$(shell git rev-parse --short HEAD 2>/dev/null)$(shell test -z "$$(git status --porcelain 2>/dev/null)" || echo -dirty)
# owner/name of the only repository whose main branch may deploy; read from origin.
GITHUB_REPO ?= $(shell git remote get-url origin 2>/dev/null | sed -E 's|\.git$$||; s|.*github\.com[:/]||')
# GitHub's OIDC subject carries the owner's and repository's numeric ids too.
# Looked up from the public API; pass them yourself for a private repository.
GITHUB_OWNER_ID ?= $(shell curl -sf https://api.github.com/repos/$(GITHUB_REPO) 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["owner"]["id"])' 2>/dev/null)
GITHUB_REPO_ID ?= $(shell curl -sf https://api.github.com/repos/$(GITHUB_REPO) 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])' 2>/dev/null)
IMAGE_TAG ?= latest
# x86_64 or arm64. arm64 is ~20% cheaper on Lambda and builds natively on
# Apple Silicon; the image platform is derived from it so the two cannot drift.
AWS_LAMBDA_ARCH ?= x86_64
IMAGE_PLATFORM = $(if $(filter arm64,$(AWS_LAMBDA_ARCH)),linux/arm64,linux/amd64)
# Every stack carries this tag, and CloudFormation copies it onto each resource
# that supports tags, so Cost Explorer and Resource Groups can find the project.
STACK_TAGS = --tags "PROJECT_NAME=$(PROJECT_NAME)"

# infra/certificate.sh reuses the CLI configured above. CloudFront only reads
# certificates from us-east-1, so that is where the frontend's goes.
CERT = AWS_CLI="$(AWS)" AWS_CERT_REGION=us-east-1 infra/certificate.sh

# $(call stack-output,<stack>,<output key>)
stack-output = $(AWS) cloudformation describe-stacks --stack-name $(1) \
	--query 'Stacks[0].Outputs[?OutputKey==`$(2)`].OutputValue' --output text

# CloudFormation refuses to update a stack that is still busy, and a Lambda in a
# VPC can keep one in *_CLEANUP_IN_PROGRESS for ~20 minutes while its network
# interfaces are released. Wait that out instead of failing.
# $(call wait-stack-idle,<stack>)
wait-stack-idle = while status=$$($(AWS) cloudformation describe-stacks --stack-name $(1) \
		--query 'Stacks[0].StackStatus' --output text 2>/dev/null | tr -d '[:space:]'); \
		case "$$status" in *_IN_PROGRESS) true ;; *) false ;; esac; do \
		echo "$(1) is $$status — waiting for it to settle..."; sleep 30; done

# A stack whose first create failed sits in ROLLBACK_COMPLETE, which
# CloudFormation can only delete. It holds no resources, so clear it and let the
# deploy start over.
# $(call clear-failed-create,<stack>)
clear-failed-create = if [ "$$($(AWS) cloudformation describe-stacks --stack-name $(1) \
		--query 'Stacks[0].StackStatus' --output text 2>/dev/null | tr -d '[:space:]')" = ROLLBACK_COMPLETE ]; then \
		echo "$(1) failed to create earlier — deleting it before retrying"; \
		$(AWS) cloudformation delete-stack --stack-name $(1) && \
		$(AWS) cloudformation wait stack-delete-complete --stack-name $(1); fi

# Fail early and clearly when .env has no credentials in it.
define require-aws-credentials
	@test -n "$$AWS_ACCESS_KEY_ID" -a -n "$$AWS_SECRET_ACCESS_KEY" || { \
		echo "AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are empty — set them in .env"; \
		exit 1; }
endef

# The password only has to be given when the backend stack is first created;
# updates (and CI, which never sees it) keep the value the stack already has.
define require-db-password
	@test -n "$$AWS_DB_PASSWORD" || $(AWS) cloudformation describe-stacks --stack-name $(APP_STACK) \
		>/dev/null 2>&1 || { \
		echo "AWS_DB_PASSWORD is empty — set it in .env for the first deploy (8+ chars, [A-Za-z0-9_-] only)"; \
		exit 1; }
endef

.PHONY: help up up-build down down-v logs ps migrate revision seed test lint fmt shell-backend psql \
        aws-whoami aws-deploy aws-ecr aws-push aws-deploy-backend aws-release aws-migrate aws-url aws-status aws-logs \
        aws-frontend-cert aws-deploy-frontend aws-frontend-url aws-destroy \
        deploy-backend deploy-frontend aws-github-oidc \
        deploy-auth aws-deploy-auth aws-auth-urls aws-auth-env \
        deploy-reports aws-deploy-reports report-invoke report-logs report-now report-queues

help:
	@grep -hE '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack
	$(COMPOSE) up

up-build: ## Rebuild images and start the whole stack
	$(COMPOSE) up --build

down: ## Stop the stack
	$(COMPOSE) down

down-v: ## Stop the stack and delete the database volume
	$(COMPOSE) down -v

logs: ## Follow logs from every service
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply database migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add column"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

seed: ## Insert demo meetings for today when the database is empty
	$(COMPOSE) exec backend python -m app.seed

test: ## Run the backend test suite against a throwaway database
	$(COMPOSE) exec db psql -U app -d postgres -tc \
		"SELECT 1 FROM pg_database WHERE datname='meetings_test'" | grep -q 1 || \
		$(COMPOSE) exec db createdb -U app meetings_test
	$(COMPOSE) exec -e DATABASE_URL=postgresql+asyncpg://app:app@db:5432/meetings_test backend pytest -q

lint: ## Lint and format-check backend and frontend (what CI runs)
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec backend ruff format --check .
	$(COMPOSE) exec frontend npm run lint
	$(COMPOSE) exec frontend npm run format:check

fmt: ## Format the backend and frontend code
	$(COMPOSE) exec backend ruff format .
	$(COMPOSE) exec frontend npm run format

shell-backend: ## Open a shell in the backend container
	$(COMPOSE) exec backend sh

psql: ## Open psql against the application database
	$(COMPOSE) exec db psql -U app -d meetings

aws-whoami: ## Verify the AWS credentials in .env
	$(require-aws-credentials)
	$(AWS) sts get-caller-identity

# The deploy contract: CI runs these same two targets, so a failed deploy can be
# reproduced on your own machine.
deploy-backend: aws-deploy-backend ## Build the image, push it to ECR, update the backend stack, migrate

deploy-frontend: aws-deploy-frontend ## Build the static bundle, sync it to S3, invalidate CloudFront

deploy-auth: aws-deploy-auth ## Create/update the Cognito user pool, Google sign-in and managed login

deploy-reports: aws-deploy-reports ## Deploy the weekly report: bucket, S3 endpoint, functions and triggers

aws-deploy: ## Deploy everything: the backend first, then the frontend built against its URL
	@$(MAKE) --no-print-directory aws-deploy-backend
	@$(MAKE) --no-print-directory aws-deploy-frontend

aws-ecr: ## Create the ECR repository for the backend image
	$(require-aws-credentials)
	$(AWS) cloudformation deploy \
		--stack-name $(ECR_STACK) \
		--template-file infra/ecr.yml \
		--no-fail-on-empty-changeset \
		$(STACK_TAGS) \
		--parameter-overrides "ProjectName=$(PROJECT_NAME)"

aws-push: aws-ecr ## Build the backend Lambda image and push it to ECR
	$(require-aws-credentials)
	@repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		echo "Pushing $$repo:$(IMAGE_TAG) ($(IMAGE_PLATFORM))"; \
		$(AWS) ecr get-login-password | docker login --username AWS --password-stdin "$${repo%%/*}"; \
		docker build --platform $(IMAGE_PLATFORM) --provenance=false \
			-f backend/Dockerfile.lambda -t "$$repo:$(IMAGE_TAG)" ./backend; \
		docker push "$$repo:$(IMAGE_TAG)"

aws-deploy-backend: aws-push ## Deploy the backend to AWS (Lambda function URL + Aurora Serverless), then migrate
	@$(MAKE) --no-print-directory aws-release

# Rolling back is releasing an older tag: make aws-release IMAGE_TAG=<commit sha>
aws-release: ## Point the backend at an image already in ECR (IMAGE_TAG), then migrate
	$(require-aws-credentials)
	$(require-db-password)
	@vpc=$$($(AWS) ec2 describe-vpcs --filters Name=isDefault,Values=true \
		--query 'Vpcs[0].VpcId' --output text | tr -d '[:space:]'); \
		test "$$vpc" != "None" -a -n "$$vpc" || { \
			echo "No default VPC in $(AWS_REGION) — pass VpcId/SubnetIds yourself"; exit 1; }; \
		subnets=$$($(AWS) ec2 describe-subnets \
			--filters Name=vpc-id,Values=$$vpc Name=default-for-az,Values=true \
			--query 'Subnets[].SubnetId' --output text | tr '[:space:]' ',' | sed 's/,*$$//'); \
		repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		digest=$$($(AWS) ecr describe-images --repository-name "$${repo#*/}" \
			--image-ids imageTag=$(IMAGE_TAG) --query 'imageDetails[0].imageDigest' \
			--output text | tr -d '[:space:]'); \
		test -n "$$digest" || { echo "No image tagged $(IMAGE_TAG) in $$repo"; exit 1; }; \
		cors="$(AWS_CORS_ORIGINS)"; \
		if [ -z "$$cors" ]; then \
			cors=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) 2>/dev/null | tr -d '[:space:]'); \
			case "$$cors" in ""|None) cors='*' ;; esac; \
		fi; \
		echo "vpc=$$vpc subnets=$$subnets image=$$repo@$$digest cors=$$cors"; \
		echo "This takes ~15 minutes the first time (Aurora is the slow part)."; \
		$(call wait-stack-idle,$(APP_STACK)); \
		$(call clear-failed-create,$(APP_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(APP_STACK) \
			--template-file infra/backend.yml \
			--capabilities CAPABILITY_IAM \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"VpcId=$$vpc" \
				"SubnetIds=$$subnets" \
				ImageUri="$$repo@$$digest" \
				"Architecture=$(AWS_LAMBDA_ARCH)" \
				"CorsOrigins=$$cors" \
				$(if $(AWS_DB_PASSWORD),"DbPassword=$$AWS_DB_PASSWORD") \
				$(if $(APP_TIMEZONE),"AppTimezone=$(APP_TIMEZONE)") \
				$(if $(AWS_SEED_DEMO_DATA),"SeedDemoData=$(AWS_SEED_DEMO_DATA)")
	@$(MAKE) --no-print-directory aws-migrate
	@$(MAKE) --no-print-directory aws-url

aws-migrate: ## Apply database migrations (invokes the backend function directly)
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) | tr -d '[:space:]'); \
		echo "Migrating ($$fn)"; \
		err=$$($(AWS) lambda invoke --function-name "$$fn" \
			--cli-binary-format raw-in-base64-out --payload '{"action":"migrate"}' \
			--query FunctionError --output text /dev/null | tr -d '[:space:]'); \
		test "$$err" = "None" || { echo "Migration failed ($$err) — see make aws-logs"; exit 1; }

aws-url: ## Print the deployed API URL
	@$(call stack-output,$(APP_STACK),ApiUrl)

aws-status: ## Show the stack outputs and the API function's state
	@$(AWS) cloudformation describe-stacks --stack-name $(APP_STACK) \
		--query 'Stacks[0].Outputs' --output table
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) | tr -d '[:space:]'); \
		$(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query '{state:State,lastUpdate:LastUpdateStatus,arch:Architectures[0],memory:MemorySize}' \
			--output table

aws-logs: ## Follow the backend function logs
	$(AWS) logs tail /aws/lambda/$(PROJECT_NAME)-backend --follow

aws-frontend-cert: ## Request and validate the HTTPS certificate for AWS_FRONTEND_DOMAIN (in us-east-1)
	$(require-aws-credentials)
	@test -n "$(AWS_FRONTEND_DOMAIN)" || { \
		echo "AWS_FRONTEND_DOMAIN is empty — set it in .env (e.g. app.example.com)"; exit 1; }
	@$(CERT) ensure "$(AWS_FRONTEND_DOMAIN)"

aws-deploy-frontend: ## Deploy the frontend to S3 + CloudFront, built against the deployed backend URL
	$(require-aws-credentials)
	@api=$$($(call stack-output,$(APP_STACK),ApiUrl) 2>/dev/null | tr -d '[:space:]'); \
		test -n "$$api" -a "$$api" != "None" || { \
			echo "No backend API found — run: make aws-deploy-backend"; exit 1; }; \
		domain=""; \
		if [ -n "$(AWS_FRONTEND_DOMAIN)" ]; then \
			cert=$$($(CERT) find "$(AWS_FRONTEND_DOMAIN)"); \
			test -n "$$cert" || { \
				echo "No issued us-east-1 certificate for $(AWS_FRONTEND_DOMAIN) — run: make aws-frontend-cert"; \
				exit 1; }; \
			zone=$$($(CERT) zone "$(AWS_FRONTEND_DOMAIN)"); \
			domain="DomainName=$(AWS_FRONTEND_DOMAIN) CertificateArn=$$cert HostedZoneId=$$zone"; \
			echo "custom domain: $(AWS_FRONTEND_DOMAIN) (Route 53 zone: $${zone:-none})"; \
		fi; \
		$(call wait-stack-idle,$(FRONTEND_STACK)); \
		$(call clear-failed-create,$(FRONTEND_STACK)); \
		echo "A new CloudFront distribution takes ~5 minutes to come up."; \
		$(AWS) cloudformation deploy \
			--stack-name $(FRONTEND_STACK) \
			--template-file infra/frontend.yml \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"PricingPlan=$(or $(AWS_CLOUDFRONT_PLAN),FREE)" \
				$$domain
	@api=$$($(call stack-output,$(APP_STACK),ApiUrl) | tr -d '[:space:]'); \
		bucket=$$($(call stack-output,$(FRONTEND_STACK),BucketName) | tr -d '[:space:]'); \
		dist=$$($(call stack-output,$(FRONTEND_STACK),DistributionId) | tr -d '[:space:]'); \
		authority=$$($(call stack-output,$(AUTH_STACK),Authority) 2>/dev/null | tr -d '[:space:]'); \
		case "$$authority" in ""|None) authority=""; echo "No auth stack — building without sign-in";; esac; \
		if [ -n "$$authority" ]; then \
			client=$$($(call stack-output,$(AUTH_STACK),ClientId) | tr -d '[:space:]'); \
			cognito=$$($(call stack-output,$(AUTH_STACK),CognitoDomain) | tr -d '[:space:]'); \
			echo "Sign-in: $$authority (client $$client)"; fi; \
		echo "Building the static export against $$api"; \
		rm -rf frontend/out; \
		docker build --target export --output type=local,dest=frontend/out \
			--build-arg NEXT_PUBLIC_API_BASE_URL="$$api" \
			--build-arg NEXT_PUBLIC_COGNITO_AUTHORITY="$$authority" \
			--build-arg NEXT_PUBLIC_COGNITO_CLIENT_ID="$$client" \
			--build-arg NEXT_PUBLIC_COGNITO_DOMAIN="$$cognito" ./frontend || exit 1; \
		echo "Uploading to s3://$$bucket"; \
		$(AWS) s3 sync frontend/out "s3://$$bucket" --delete --exclude "*.html" \
			--cache-control "public,max-age=31536000,immutable" --only-show-errors || exit 1; \
		$(AWS) s3 sync frontend/out "s3://$$bucket" --delete --exclude "*" --include "*.html" \
			--cache-control "no-cache" --only-show-errors || exit 1; \
		$(AWS) cloudfront create-invalidation --distribution-id "$$dist" --paths "/*" \
			--query 'Invalidation.Status' --output text
	@$(MAKE) --no-print-directory aws-frontend-url
	@if [ -z "$(AWS_CORS_ORIGINS)" ]; then \
		allowed=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) | tr -d '[:space:]'); \
		fn=$$($(call stack-output,$(APP_STACK),FunctionName) | tr -d '[:space:]'); \
		current=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Environment.Variables.CORS_ORIGINS' --output text | tr -d '[:space:]'); \
		test "$$current" = "$$allowed" || echo "The API still allows CORS_ORIGINS=$$current — run make aws-deploy-backend to limit it to $$allowed"; \
	fi
	@if [ -n "$(AWS_FRONTEND_DOMAIN)" ] && [ -z "$$($(CERT) zone "$(AWS_FRONTEND_DOMAIN)")" ]; then \
		echo "Point $(AWS_FRONTEND_DOMAIN) at the distribution: CNAME $$($(call stack-output,$(FRONTEND_STACK),DistributionDomain) | tr -d '[:space:]')"; \
	fi

aws-github-oidc: ## Create the GitHub OIDC provider and the role CI deploys with (run once, as admin)
	$(require-aws-credentials)
	@test -n "$(GITHUB_REPO)" || { echo "GITHUB_REPO is empty — pass GITHUB_REPO=owner/name"; exit 1; }
	@test -n "$(GITHUB_OWNER_ID)" -a -n "$(GITHUB_REPO_ID)" || { \
		echo "Could not look up $(GITHUB_REPO) on GitHub — pass GITHUB_OWNER_ID=... GITHUB_REPO_ID=..."; exit 1; }
	@provider=$$($(AWS) iam list-open-id-connect-providers \
			--query 'OpenIDConnectProviderList[?ends_with(Arn, `/token.actions.githubusercontent.com`)].Arn' \
			--output text | tr -d '[:space:]'); \
		create=true; \
		if [ -n "$$provider" ] && ! $(AWS) cloudformation describe-stack-resource --stack-name $(GITHUB_STACK) \
				--logical-resource-id GitHubOidcProvider >/dev/null 2>&1; then \
			echo "Reusing the account's existing GitHub OIDC provider"; create=false; fi; \
		echo "Trusting $(GITHUB_REPO) (owner id $(GITHUB_OWNER_ID), repo id $(GITHUB_REPO_ID)), branch main"; \
		$(AWS) cloudformation deploy \
			--stack-name $(GITHUB_STACK) \
			--template-file infra/github-oidc.yml \
			--capabilities CAPABILITY_NAMED_IAM \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"GitHubRepo=$(GITHUB_REPO)" \
				"GitHubOwnerId=$(GITHUB_OWNER_ID)" \
				"GitHubRepoId=$(GITHUB_REPO_ID)" \
				"CreateOidcProvider=$$create"
	@$(call stack-output,$(GITHUB_STACK),RoleArn)

# Callback and logout URLs follow the frontend stack's origins (its CloudFront
# URL, plus AWS_FRONTEND_DOMAIN once one is set) and local development. They
# must match the frontend's redirect_uri exactly, trailing slash included.
aws-deploy-auth: ## Deploy the Cognito user pool, Google sign-in and managed login
	$(require-aws-credentials)
	@test -n "$(AWS_COGNITO_DOMAIN_PREFIX)" || { \
		echo "AWS_COGNITO_DOMAIN_PREFIX is empty — set it in .env (e.g. successfuls)"; exit 1; }
	@test -n "$(GOOGLE_CLIENT_ID)" -a -n "$$GOOGLE_CLIENT_SECRET" || \
		$(AWS) cloudformation describe-stacks --stack-name $(AUTH_STACK) >/dev/null 2>&1 || { \
		echo "GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET are empty — set them in .env for the first deploy"; exit 1; }
	@origins=$$($(call stack-output,$(FRONTEND_STACK),AllowedOrigins) 2>/dev/null | tr -d '[:space:]'); \
		case "$$origins" in ""|None) echo "No frontend stack found — run make deploy-frontend first"; exit 1;; esac; \
		origins="$$origins,http://localhost:$(or $(FRONTEND_PORT),3000)"; \
		callbacks=$$(echo "$$origins" | tr ',' '\n' | sed 's|$$|/auth/callback/|' | paste -sd, -); \
		logouts=$$(echo "$$origins" | tr ',' '\n' | sed 's|$$|/|' | paste -sd, -); \
		echo "Callback URLs: $$callbacks"; \
		echo "Logout URLs:   $$logouts"; \
		$(call wait-stack-idle,$(AUTH_STACK)); \
		$(call clear-failed-create,$(AUTH_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(AUTH_STACK) \
			--template-file infra/auth.yml \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"DomainPrefix=$(AWS_COGNITO_DOMAIN_PREFIX)" \
				"CallbackUrls=$$callbacks" \
				"LogoutUrls=$$logouts" \
				$(if $(GOOGLE_CLIENT_ID),"GoogleClientId=$(GOOGLE_CLIENT_ID)") \
				$(if $(GOOGLE_CLIENT_SECRET),"GoogleClientSecret=$$GOOGLE_CLIENT_SECRET")
	@$(MAKE) --no-print-directory aws-auth-urls
	@echo "Rebuild the site so it picks up the sign-in settings: make deploy-frontend"

aws-auth-urls: ## Print the login page, the Cognito domain and the URI to register at Google
	@site=$$($(call stack-output,$(FRONTEND_STACK),SiteUrl) | tr -d '[:space:]'); \
		echo "Login page:           $${site%/}/login/"; \
		echo "Cognito domain:       $$($(call stack-output,$(AUTH_STACK),CognitoDomain) | tr -d '[:space:]')"; \
		echo "Google redirect URI:  $$($(call stack-output,$(AUTH_STACK),GoogleRedirectUri) | tr -d '[:space:]')"

aws-auth-env: ## Print the NEXT_PUBLIC_COGNITO_* lines for .env, to sign in from localhost
	@echo "NEXT_PUBLIC_COGNITO_AUTHORITY=$$($(call stack-output,$(AUTH_STACK),Authority) | tr -d '[:space:]')"
	@echo "NEXT_PUBLIC_COGNITO_CLIENT_ID=$$($(call stack-output,$(AUTH_STACK),ClientId) | tr -d '[:space:]')"
	@echo "NEXT_PUBLIC_COGNITO_DOMAIN=$$($(call stack-output,$(AUTH_STACK),CognitoDomain) | tr -d '[:space:]')"

# The builder runs where the backend function runs: the VPC, its subnets and
# security group, and the route tables of those subnets are read from that
# function rather than configured. A subnet without its own route table uses
# the VPC's main one. The image is built from the working tree (see
# REPORTS_IMAGE_TAG) for the backend's architecture. The database password is
# only needed for the first deploy; updates keep the stack's value.
aws-deploy-reports: ## Deploy the weekly report stack (bucket, S3 endpoint, builder, schedule)
	$(require-aws-credentials)
	@test -n "$$AWS_DB_PASSWORD" || $(AWS) cloudformation describe-stacks --stack-name $(REPORTS_STACK) \
		>/dev/null 2>&1 || { echo "AWS_DB_PASSWORD is empty — set it in .env for the first deploy"; exit 1; }
	@test -n "$(REPORT_EMAIL)" || { \
		echo "REPORT_EMAIL is empty — set it in .env: the SES identity, sender and recipient"; exit 1; }
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) 2>/dev/null | tr -d '[:space:]'); \
		backend_arch=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Architectures[0]' --output text | tr -d '[:space:]'); \
		test "$$backend_arch" = "$(AWS_LAMBDA_ARCH)" || { \
			echo "The backend runs on $$backend_arch: run make deploy-reports AWS_LAMBDA_ARCH=$$backend_arch"; exit 1; }
	@$(MAKE) --no-print-directory aws-push IMAGE_TAG=$(REPORTS_IMAGE_TAG)
	@fn=$$($(call stack-output,$(APP_STACK),FunctionName) 2>/dev/null | tr -d '[:space:]'); \
		case "$$fn" in ""|None) echo "No backend stack found — run make deploy-backend first"; exit 1;; esac; \
		vpc=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'VpcConfig.VpcId' --output text | tr -d '[:space:]'); \
		subnets=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'VpcConfig.SubnetIds' --output text); \
		sg=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'VpcConfig.SecurityGroupIds[0]' --output text | tr -d '[:space:]'); \
		arch=$$($(AWS) lambda get-function-configuration --function-name "$$fn" \
			--query 'Architectures[0]' --output text | tr -d '[:space:]'); \
		repo=$$($(call stack-output,$(ECR_STACK),RepositoryUri) | tr -d '[:space:]'); \
		digest=$$($(AWS) ecr describe-images --repository-name "$${repo#*/}" \
			--image-ids imageTag=$(REPORTS_IMAGE_TAG) --query 'imageDetails[0].imageDigest' \
			--output text | tr -d '[:space:]'); \
		test -n "$$digest" -a "$$digest" != "None" || { echo "No image tagged $(REPORTS_IMAGE_TAG)"; exit 1; }; \
		image="$$repo@$$digest"; \
		db=$$($(call stack-output,$(APP_STACK),DatabaseEndpoint) | tr -d '[:space:]'); \
		main=$$($(AWS) ec2 describe-route-tables \
			--filters Name=vpc-id,Values=$$vpc Name=association.main,Values=true \
			--query 'RouteTables[0].RouteTableId' --output text | tr -d '[:space:]'); \
		tables=$$(for s in $$subnets; do \
			rt=$$($(AWS) ec2 describe-route-tables --filters Name=association.subnet-id,Values=$$s \
				--query 'RouteTables[0].RouteTableId' --output text | tr -d '[:space:]'); \
			if [ -z "$$rt" ] || [ "$$rt" = None ]; then rt=$$main; fi; echo "$$rt"; \
			done | sort -u | paste -sd, -); \
		echo "vpc=$$vpc route tables=$$tables sg=$$sg arch=$$arch"; \
		echo "image=$(REPORTS_IMAGE_TAG) → $$image"; \
		echo "schedule=$(REPORT_SCHEDULE) ($(or $(APP_TIMEZONE),Europe/Kyiv)) email=$(REPORT_EMAIL)"; \
		$(call wait-stack-idle,$(REPORTS_STACK)); \
		$(call clear-failed-create,$(REPORTS_STACK)); \
		$(AWS) cloudformation deploy \
			--stack-name $(REPORTS_STACK) \
			--template-file infra/reports.yml \
			--capabilities CAPABILITY_IAM \
			--no-fail-on-empty-changeset \
			$(STACK_TAGS) \
			--parameter-overrides \
				"ProjectName=$(PROJECT_NAME)" \
				"VpcId=$$vpc" \
				"RouteTableIds=$$tables" \
				"SubnetIds=$$(echo $$subnets | tr ' ' ',')" \
				"SecurityGroupId=$$sg" \
				"ImageUri=$$image" \
				"Architecture=$$arch" \
				"DbEndpoint=$$db" \
				"ScheduleExpression=$(REPORT_SCHEDULE)" \
				"ReportEmail=$(REPORT_EMAIL)" \
				$(if $(APP_TIMEZONE),"AppTimezone=$(APP_TIMEZONE)") \
				$(if $(AWS_DB_PASSWORD),"DbPassword=$$AWS_DB_PASSWORD")
	@echo "Reports bucket: s3://$$($(call stack-output,$(REPORTS_STACK),BucketName) | tr -d '[:space:]')"

# Calls the builder directly, as the schedule does, but for a chosen week.
# WEEK is optional: without it the builder takes the previous ISO week.
report-invoke: ## Build a report now by invoking the builder directly: make report-invoke WEEK=2026-W40
	$(require-aws-credentials)
	@fn=$$($(call stack-output,$(REPORTS_STACK),BuilderFunctionName) | tr -d '[:space:]'); \
		payload='{"source": "manual"$(if $(WEEK),$(comma) "week": "$(WEEK)")}'; \
		echo "Invoking $$fn with $$payload"; \
		$(AWS) lambda invoke --function-name "$$fn" --cli-binary-format raw-in-base64-out \
			--cli-read-timeout 180 --payload "$$payload" /dev/stdout \
			--query 'FunctionError' --output text

# The on-demand path: the same message the schedule sends, on the same queue.
# This is how an old report is rebuilt. Without WEEK the builder takes the
# previous ISO week, exactly as on Monday morning.
report-now: ## Request a report through the queue: make report-now WEEK=2026-W39
	$(require-aws-credentials)
	@queue=$$($(call stack-output,$(REPORTS_STACK),RequestQueueUrl) | tr -d '[:space:]'); \
		body='{"week": $(if $(WEEK),"$(WEEK)",null), "source": "make"}'; \
		echo "Sending $$body"; \
		$(AWS) sqs send-message --queue-url "$$queue" --message-body "$$body" \
			--query 'MessageId' --output text | sed 's/^/MessageId: /'

# The output name has to be spelled out per call: stack-output puts it inside
# a single-quoted --query, where a shell variable would not be expanded.
report-queues: ## Messages waiting, in flight and in the dead-letter queue
	@for url in $$($(call stack-output,$(REPORTS_STACK),RequestQueueUrl)) \
			$$($(call stack-output,$(REPORTS_STACK),DeadLetterQueueUrl)); do \
		$(AWS) sqs get-queue-attributes --queue-url "$$url" \
			--attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
			--query 'Attributes.[ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible]' \
			--output text | awk -v q="$${url##*/}" '{printf "%-40s waiting %s, in flight %s\n", q, $$1, $$2}'; \
	done

report-logs: ## Show the last hour of the report builder's and mailer's logs
	@echo "--- builder"; $(AWS) logs tail "$$($(call stack-output,$(REPORTS_STACK),BuilderLogGroup) | tr -d '[:space:]')" \
		--since 1h --format short
	@echo "--- mailer"; $(AWS) logs tail "$$($(call stack-output,$(REPORTS_STACK),MailerLogGroup) | tr -d '[:space:]')" \
		--since 1h --format short

aws-frontend-url: ## Print the deployed site URL
	@$(call stack-output,$(FRONTEND_STACK),SiteUrl)

aws-destroy: ## Delete every stack, including the database and its data
	$(require-aws-credentials)
	@printf 'Delete %s, %s, %s, %s, %s and %s? The Aurora cluster, every user account and every report go with them (no snapshot). Type yes: ' \
		"$(REPORTS_STACK)" "$(AUTH_STACK)" "$(GITHUB_STACK)" "$(FRONTEND_STACK)" "$(APP_STACK)" "$(ECR_STACK)"; \
		read answer; test "$$answer" = "yes" || { echo "Aborted."; exit 1; }
	@bucket=$$($(call stack-output,$(FRONTEND_STACK),BucketName) 2>/dev/null | tr -d '[:space:]'); \
		if [ -n "$$bucket" ] && [ "$$bucket" != "None" ]; then \
			echo "Emptying s3://$$bucket"; \
			$(AWS) s3 rm "s3://$$bucket" --recursive --only-show-errors || true; \
		fi
	@reports=$$($(call stack-output,$(REPORTS_STACK),BucketName) 2>/dev/null | tr -d '[:space:]'); \
		if [ -n "$$reports" ] && [ "$$reports" != "None" ]; then \
			echo "Emptying s3://$$reports"; \
			$(AWS) s3 rm "s3://$$reports" --recursive --only-show-errors || true; \
		fi
	-$(AWS) cloudformation delete-stack --stack-name $(REPORTS_STACK)
	-$(AWS) cloudformation wait stack-delete-complete --stack-name $(REPORTS_STACK)
	-$(AWS) cloudformation delete-stack --stack-name $(AUTH_STACK)
	-$(AWS) cloudformation wait stack-delete-complete --stack-name $(AUTH_STACK)
	-$(AWS) cloudformation delete-stack --stack-name $(GITHUB_STACK)
	-$(AWS) cloudformation wait stack-delete-complete --stack-name $(GITHUB_STACK)
	-$(AWS) cloudformation delete-stack --stack-name $(FRONTEND_STACK)
	-$(AWS) cloudformation wait stack-delete-complete --stack-name $(FRONTEND_STACK)
	@echo "Deleting $(APP_STACK) — Lambda releases its VPC network interfaces slowly, allow ~20 minutes."
	$(AWS) cloudformation delete-stack --stack-name $(APP_STACK)
	$(AWS) cloudformation wait stack-delete-complete --stack-name $(APP_STACK)
	$(AWS) cloudformation delete-stack --stack-name $(ECR_STACK)
	$(AWS) cloudformation wait stack-delete-complete --stack-name $(ECR_STACK)
	@echo "All stacks deleted."
