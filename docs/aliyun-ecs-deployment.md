# Alibaba Cloud ECS Deployment

This project deploys Open WebUI to Alibaba Cloud in `cn-beijing` with:

- GitHub Actions for build, infrastructure, and deploy.
- Alibaba Cloud ACR Personal Edition for the image repository.
- ECS + Docker Compose for runtime.
- Terraform for VPC, VSwitch, security group, EIP, ECS, data disk, snapshot policy, RDS PostgreSQL, and ECS RAM role.
- ECS Cloud Assistant for deployment, so SSH does not need to be open.

## Manual Prerequisites

ACR Personal Edition must be created manually because it is intended for development/test use and does not support API-based resource management.

Create these manually in Alibaba Cloud:

- ACR Personal Edition instance in `cn-beijing`.
- ACR namespace, then a repository named `open-webui` unless you set a different `ACR_REPOSITORY`.
- A dedicated RAM user with AccessKey for GitHub Actions.
- A globally unique OSS bucket name to use as `TF_STATE_BUCKET`.

Alibaba Cloud shows an AccessKey secret only when the key is created. If it was not saved, create a new AccessKey for the dedicated RAM user.

## GitHub Environment

Create a GitHub Environment named `aliyun-hai`.

Environment secrets:

- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `OPEN_WEBUI_ENV_HAI_B64`

Optional environment secrets:

- `ACR_USERNAME`
- `ACR_PASSWORD`

By default, workflows use `aliyun/acr-login@v1` with the Alibaba Cloud AccessKey to log in to ACR. If ACR returns `denied: requested access to the resource is denied` while pushing the image, either grant that RAM user push permission to the repository or set `ACR_USERNAME` and `ACR_PASSWORD` from the ACR Access Credential page. When both ACR secrets are present, the build and deploy workflows use them before trying AccessKey-based ACR login.

Generate `OPEN_WEBUI_ENV_HAI_B64` locally without printing the secret values:

```sh
base64 < .env.hai | tr -d '\n'
```

Or run the helper script. It uses hidden prompts for secret values and reads `.env.hai` directly when present:

```sh
deploy/aliyun/scripts/configure-github-env.sh
```

To update only ACR credentials after the environment already exists, run:

```sh
gh secret set ACR_USERNAME --env aliyun-hai
gh secret set ACR_PASSWORD --env aliyun-hai
```

Environment variables:

- `ALIYUN_REGION=cn-beijing`
- `ACR_REGISTRY=registry.cn-beijing.aliyuncs.com`
- `ACR_NAMESPACE=<your-acr-namespace>`
- `ACR_REPOSITORY=open-webui`
- `ACR_INSTANCE_ID=<enterprise-instance-id>` only for ACR Enterprise Edition
- `APP_PORT=3000`
- `TF_STATE_BUCKET=<globally-unique-oss-bucket-name>`
- `TF_LOCK_INSTANCE=ow-hai-tf-lock`
- `TF_LOCK_TABLE=terraform_locks`

## Provisioning Order

1. Run the `Alibaba Cloud Infra` workflow with `stack=bootstrap` and `apply=true`.
2. Run the `Alibaba Cloud Infra` workflow with `stack=aliyun` and `apply=false`; inspect the plan.
3. Run the same workflow with `stack=aliyun` and `apply=true`.
4. Run `Alibaba Cloud Deploy`, or push to `main`.

The deploy workflow builds and pushes:

```text
registry.cn-beijing.aliyuncs.com/<ACR_NAMESPACE>/open-webui:git-<commit-sha>
registry.cn-beijing.aliyuncs.com/<ACR_NAMESPACE>/open-webui:latest
```

Then it uploads the Compose file, `.env.hai`, and Docker auth config to ECS with Cloud Assistant and runs the deployment command on the instance.

## Database And Redis

Terraform creates an ApsaraDB RDS PostgreSQL instance and outputs a sensitive `database_url`. The deploy workflow reads that output and injects it into the container as:

- `DATABASE_URL`
- `PGVECTOR_DB_URL`

Redis is not created by default. The current deployment runs a single Open WebUI container on one ECS instance, and this version of Open WebUI treats `REDIS_URL` and `WEBSOCKET_MANAGER` as optional. Add Redis later only if you deploy multiple Open WebUI instances or need a shared websocket/config state across replicas.

If Redis is added later, set `redis_url` and `websocket_manager = "redis"` in Terraform variables and rerun infra + deploy.

## Local Terraform

Bootstrap:

```sh
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap apply \
  -var "region=cn-beijing" \
  -var "state_bucket_name=<globally-unique-oss-bucket-name>"
```

Application infrastructure:

```sh
terraform -chdir=infra/aliyun init \
  -backend-config="bucket=<globally-unique-oss-bucket-name>" \
  -backend-config="key=open-webui/hai/terraform.tfstate" \
  -backend-config="region=cn-beijing" \
  -backend-config="tablestore_endpoint=https://ow-hai-tf-lock.cn-beijing.ots.aliyuncs.com" \
  -backend-config="tablestore_table=terraform_locks"

terraform -chdir=infra/aliyun plan
terraform -chdir=infra/aliyun apply
```

## Security Notes

- `.env.hai` stays ignored by Git and Docker build context.
- Public test access currently opens `APP_PORT` to `0.0.0.0/0`.
- SSH is closed unless `ssh_ingress_cidr_blocks` is explicitly set in Terraform.
- For production, replace public IP testing with domain + HTTPS and restrict ingress.
