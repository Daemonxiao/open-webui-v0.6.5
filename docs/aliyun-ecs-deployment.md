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
- `NEW_API_SESSION_SECRET`
- `NEW_API_CRYPTO_SECRET`

Optional environment secrets:

- `ACR_USERNAME`
- `ACR_PASSWORD`
- `NEW_API_OPENWEBUI_TOKEN`

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
- `NEW_API_PORT=3001`
- `NEW_API_SOURCE_IMAGE=calciumion/new-api:v1.0.0-rc.8`
- `TF_STATE_BUCKET=<globally-unique-oss-bucket-name>`
- `TF_LOCK_INSTANCE=ow-hai-tf-lock`
- `TF_LOCK_TABLE=terraform_locks`
- `ECS_CPU_CORE_COUNT=8`
- `ECS_MEMORY_SIZE=16`

## Provisioning Order

1. Run the `Alibaba Cloud Infra` workflow with `stack=bootstrap` and `apply=true`.
2. Run the `Alibaba Cloud Infra` workflow with `stack=aliyun` and `apply=false`; inspect the plan.
3. Run the same workflow with `stack=aliyun` and `apply=true`.
4. Run `Deploy Gateway (New API) to Alibaba Cloud`.
5. Open the New API web UI, configure upstream channels, and create a token for Open WebUI.
6. Configure that token in the Open WebUI web UI, or save it as the optional `NEW_API_OPENWEBUI_TOKEN` environment secret.
7. Run `Deploy Open WebUI to Alibaba Cloud`, or push to `main`.

The Open WebUI deploy workflow builds and pushes:

```text
registry.cn-beijing.aliyuncs.com/<ACR_NAMESPACE>/open-webui:git-<commit-sha>
registry.cn-beijing.aliyuncs.com/<ACR_NAMESPACE>/open-webui:latest
```

Then it uploads the Compose file, `.env.hai`, and Docker auth config to ECS with Cloud Assistant and runs the deployment command on the instance.

The New API deploy workflow mirrors the pinned public image from `NEW_API_SOURCE_IMAGE` to the existing ACR repository, then deploys the mirrored ACR image to ECS. This avoids slow or blocked Docker Hub pulls from the ECS instance. The default source image is `calciumion/new-api:v1.0.0-rc.8`, and the New API web UI is exposed on `NEW_API_PORT`.

## New API Gateway

New API is deployed as a separate container on the same ECS instance as Open WebUI. Both containers are attached to the `open-webui` container network:

- Public web UI and API: `http://<EIP>:3001`
- OpenAI-compatible endpoint configured in Open WebUI: `http://host.containers.internal:3001/v1`

When `NEW_API_OPENWEBUI_TOKEN` is set as an environment secret, Open WebUI receives:

- `ENABLE_OPENAI_API=True`
- `OPENAI_API_BASE_URL=http://host.containers.internal:3001/v1`
- `OPENAI_API_KEY=$NEW_API_OPENWEBUI_TOKEN`

If you configure the OpenAI-compatible connection manually in the Open WebUI web UI, leave `NEW_API_OPENWEBUI_TOKEN` unset. The deploy workflow will not overwrite that UI-managed connection.

`host.containers.internal` is used because Alibaba Cloud Linux images may provide Docker through Podman compatibility, where container DNS aliases are less reliable than routing through the host port.

The New API web UI is intentionally deployed first, because the Open WebUI token is created inside New API after the first New API deployment. You can either configure that token manually in the Open WebUI web UI, or save it as a GitHub environment secret:

```sh
gh secret set NEW_API_OPENWEBUI_TOKEN --env aliyun-hai
```

Then rerun `Deploy Open WebUI to Alibaba Cloud`.

## Database And Redis

Terraform creates an ApsaraDB RDS PostgreSQL instance and outputs a sensitive `database_url`. The deploy workflow reads that output and injects it into the container as:

- `DATABASE_URL`
- `PGVECTOR_DB_URL`

Terraform also creates a separate PostgreSQL database and account for New API in the same RDS instance. New API receives that connection string as:

- `SQL_DSN`

The Open WebUI and New API databases are intentionally separate even though they share one RDS instance. This avoids schema and migration coupling between the two applications.

Redis is not created by default. The current deployment runs a single Open WebUI container on one ECS instance, and this version of Open WebUI treats `REDIS_URL` and `WEBSOCKET_MANAGER` as optional. Add Redis later only if you deploy multiple Open WebUI instances or need a shared websocket/config state across replicas.

If Redis is added later, set `redis_url` and `websocket_manager = "redis"` in Terraform variables and rerun infra + deploy.

## ECS Sizing

The default Alibaba Cloud infra workflow now provisions a single 8C16G ECS instance by passing:

- `ecs_cpu_core_count=8`
- `ecs_memory_size=16`

Leave `instance_type` empty to let Terraform choose the lowest-priced available instance class in the selected zone that matches 8C16G. To downgrade later, set the GitHub Environment variables `ECS_CPU_CORE_COUNT=4` and `ECS_MEMORY_SIZE=8`, run the `Alibaba Cloud Infra` workflow with `stack=aliyun` and `apply=false`, inspect the plan, then rerun with `apply=true` during a maintenance window.

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
- Public test access currently opens `APP_PORT` and `NEW_API_PORT` to `0.0.0.0/0`.
- New API exposes an administrative web UI. Change default credentials immediately after first login and restrict ingress before production use.
- SSH is closed unless `ssh_ingress_cidr_blocks` is explicitly set in Terraform.
- For production, replace public IP testing with domain + HTTPS and restrict ingress.
