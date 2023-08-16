# AppMicroserviceAction

Github Action to deploy all resource for a microservice
File should match this path `.finalcad/application.yaml`.

Refer to `application.cue` file in `FinalCAD/terraform-app-microservice` for all keys available [here](https://github.com/FinalCAD/terraform-app-microservice/blob/master/application.cue)

You can find a list of all available secrets keys on this [page](https://finalcad.atlassian.net/wiki/spaces/INFRA/pages/3213590529/Security+secrets)

## Inputs
### `app-name`
[**Required**] Application ID to identify the apps in eks-apps

### `app-suffix`
Add suffix to resources for mono-repoistory mainly

### `aws-role`
[**Required**] AWS role allowing Secret manager usage

### `terraform-version`
Terraform version to use, Default: latest

### `terragrunt-version`
Terragrunt version to use, Default: latest

### `application-repo`
Repository containing terraform code for applicaton resource creation, Default: FinalCAD/terraform-app-microservice

### `application-ref`
Reference to use for `application-repo` repository, Default: master

### `github-token`
Github token to avoid limit rate when pulling package

### `github-ssh`
[**Required**] Github ssh key to pull `appsecret-repo` repository

### `environment`
[**Required**] Finalcad envrionment: production, staging, sandbox

### `region-friendly`
Finalcad region: `frankfurt` or `tokyo`, Default: frankfurt

### `application-file`
Path for application file definition, Default: .finalcad/application.yaml

### `dry-run`
Dry run, will not trigger apply, Default: false

## Usage

```yaml
- name: Push secrets
  uses: FinalCAD/AppMicroserviceAction@v1.0.0
  with:
    github-ssh: ${{ secrets.GH_DEPLOY_SSH }}
    environment: sandbox
    region-friendly: frankfurt
    app-name: api1-service-api
    aws-role: ${{ secrets.DEPLOY_ROLE_MASTER }}
```
