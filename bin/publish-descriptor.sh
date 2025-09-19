#!/usr/bin/env bash
set -o pipefail

bin="$(realpath "${BASH_SOURCE}")" &&
bindir="$(dirname "${bin}")" &&
basedir="$(dirname "${bindir}")" &&
true || exit $?

function check.env() {
  local rc=0

  while [[ $# > 0 ]]; do
    local var="$1"; shift

    [[ ! -z "${!var}" ]] || {
      rc=$?
      echo "[ERROR] Missing '${var}' environment variable" >&2
    }
  done

  return $rc
}

function check.exe() {
  local rc=0

  while [[ $# > 0 ]]; do
    local exe="$1"; shift

    type "${exe}" >/dev/null 2>&1 || {
      rc=$?
      echo "[ERROR] Missing '${exe}' command" >&2
    }
  done

  return $rc
}

function git.repo.descriptor() {
  git -C "${DEPLOYMENT_DESCRIPTOR_GIT_REPOSITORY}" "$@"
}
function git.repo.application() {
  git -C "${MICROSERVICE_GIT_REPOSITORY}" "$@"
}
function git.repo.terraform() {
  git -C "${TERRAFORM_GIT_REPOSITORY}" "$@"
}

function git.metadata() {
  local repository_key="$1"; shift
  local git_fn="git.repo.${repository_key}"

  local git_repository=''
  local git_branch=''
  local git_commit=''
  local git_committer_name=''
  local git_committer_email=''
  local git_committer_date=''
  local git_author_name=''
  local git_author_email=''
  local git_author_date=''
  local git_refs=()

  git_repository="$("${git_fn}" remote get-url origin)" || {
    rc=$?
    echo "[ERROR] Cannot get Git repository" >&2
    return $rc
  }
  git_branch="$("${git_fn}" rev-parse --symbolic-full-name HEAD)" || {
    rc=$?
    echo "[ERROR] Cannot get Git branch" >&2
    return $rc
  }
  git_commit="$("${git_fn}" rev-parse HEAD)" || {
    rc=$?
    echo "[ERROR] Cannot get Git commit" >&2
    return $rc
  }

  git_committer_name="$("${git_fn}" show --format='%cN' --no-patch)" || {
    rc=$?
    echo "[ERROR] Cannot get Git committer name" >&2
    return $rc
  }
  git_committer_email="$("${git_fn}" show --format='%cE' --no-patch)" || {
    rc=$?
    echo "[ERROR] Cannot get Git committer email" >&2
    return $rc
  }
  git_committer_date="$("${git_fn}" show --format='%cI' --no-patch)" || {
    rc=$?
    echo "[ERROR] Cannot get Git committer date" >&2
    return $rc
  }

  git_author_name="$("${git_fn}" show --format='%aN' --no-patch)" || {
    rc=$?
    echo "[ERROR] Cannot get Git author name" >&2
    return $rc
  }
  git_author_email="$("${git_fn}" show --format='%aE' --no-patch)" || {
    rc=$?
    echo "[ERROR] Cannot get Git author email" >&2
    return $rc
  }
  git_author_date="$("${git_fn}" show --format='%aI' --no-patch)" || {
    rc=$?
    echo "[ERROR] Cannot get Git author date" >&2
    return $rc
  }

  git_refs=( $("${git_fn}" for-each-ref --format '%(refname)' --points-at HEAD --exclude 'refs/remotes/') ) &&
  git_refs="$(jq --null-input '$ARGS.positional' --args "${git_refs[@]}")" &&
  true || {
    rc=$?
    echo "[ERROR] Cannot list Git refs" >&2
    return $rc
  }

  jq \
    --null-input \
    --arg git_repository "${git_repository}" \
    --arg git_branch "${git_branch}" \
    --arg git_commit "${git_commit}" \
    --arg git_committer_name "${git_committer_name}" \
    --arg git_committer_email "${git_committer_email}" \
    --arg git_committer_date "${git_committer_date}" \
    --arg git_author_name "${git_author_name}" \
    --arg git_author_email "${git_author_email}" \
    --arg git_author_date "${git_author_date}" \
    --argjson git_refs "${git_refs}" \
    '{
      repository: $git_repository,
      branch: $git_branch,
      commit: $git_commit,
      committer: {
        name: $git_committer_name,
        email: $git_committer_email,
        date: $git_committer_date,
      },
      author: {
        name: $git_author_name,
        email: $git_author_email,
        date: $git_author_date,
      },
      refs: $git_refs,
    }' || {
    rc=$?
    echo "[ERROR] Cannot create Git metadata JSON for ${repository_key} repository" >&2
    return $rc
  }
}

function main() {
  main.exec "$@"; local rc=$?

  if [[ $rc == 0 ]]; then
    echo
    echo "[INFO] Success"
  else
    {
      [[ ! -f "${descriptor_directory}/metadata.json" ]] || {
        echo
        echo "---------- metadata.json ----------"
        cat "${descriptor_directory}/metadata.json"
        echo "-----------------------------------"
      }
      echo
      echo "[ERROR] Failure"
    } >&2
  fi

  return $rc
}

function main.exec() {
  local rc=0

  check.env \
    DEPLOYMENT_DESCRIPTOR_FILE \
    DEPLOYMENT_DESCRIPTOR_GIT_REPOSITORY \
    FINALCAD_ENVIRONMENT \
    FINALCAD_REGION_FRIENDLY \
    GITHUB_ACTION_PATH \
    MICROSERVICE_GIT_REPOSITORY \
    TERRAFORM_GIT_REPOSITORY \
    TF_VAR_application_id \
  &&
  check.exe \
    git \
    jq \
  &&
  true || return $?

  [[ -d "${DEPLOYMENT_DESCRIPTOR_GIT_REPOSITORY}" ]] || {
    rc=$?
    echo "[ERROR] DEPLOYMENT_DESCRIPTOR_GIT_REPOSITORY '${DEPLOYMENT_DESCRIPTOR_GIT_REPOSITORY}' is not a directory" >&2
  }
  [[ -f "${DEPLOYMENT_DESCRIPTOR_FILE}" ]] || {
    rc=$?
    echo "[ERROR] DEPLOYMENT_DESCRIPTOR_FILE '${DEPLOYMENT_DESCRIPTOR_FILE}' is not a file" >&2
  }
  [[ $rc == 0 ]] || return $rc

  local application_name="${TF_VAR_application_id}"
  [[ -z "${TF_VAR_application_suffix}" ]] || application_name+="_${TF_VAR_application_suffix}"
  descriptor_directory="${DEPLOYMENT_DESCRIPTOR_GIT_REPOSITORY}/microservice/${FINALCAD_ENVIRONMENT}/${FINALCAD_REGION_FRIENDLY}/${application_name}"

  echo "[INFO] Initialize descriptor directory '${descriptor_directory}'"
  [[ ! -d "${descriptor_directory}" ]] || rm -rf "${descriptor_directory}"
  mkdir --parents "${descriptor_directory}" || {
    rc=$?
    echo "[ERROR] Cannot create descriptor directory '${descriptor_directory}'" >&2
    return $rc
  }

  echo "[INFO] Copy descriptor file"
  cp "${DEPLOYMENT_DESCRIPTOR_FILE}" "${descriptor_directory}/application.yaml" || {
    rc=$?
    echo "[ERROR] Cannot copy descriptor file '${DEPLOYMENT_DESCRIPTOR_FILE}' to '${descriptor_directory}/application.yaml'" >&2
    return $rc
  }

  echo "[INFO] Create environment file"
  cat > "${descriptor_directory}/application.shrc" <<EOF ||
export TF_VAR_application_id='${TF_VAR_application_id}'
export TF_VAR_application_suffix='${TF_VAR_application_suffix}'
EOF
  {
    rc=$?
    echo "[ERROR] Cannot create environment file '${descriptor_directory}/application.shrc'" >&2
    return $rc
  }

  echo "[INFO] Collect Git metadata"
  local metadata_application_git=''
  metadata_application_git="$(git.metadata application)" || {
    rc=$?
    echo "[ERROR] Cannot collect application Git metadata" >&2
    return $rc
  }
  local metadata_terraform_git=''
  metadata_terraform_git="$(git.metadata terraform)" || {
    rc=$?
    echo "[ERROR] Cannot collect terraform Git metadata" >&2
    return $rc
  }

  echo "[INFO] Create metadata file"
  jq \
    --null-input \
    --argjson metadata_application_git "${metadata_application_git}" \
    --arg metadata_application_ci_actor_id "${GITHUB_ACTOR_ID}" \
    --arg metadata_application_ci_actor_name "${GITHUB_ACTOR}" \
    --arg metadata_application_ci_job "${GITHUB_JOB}" \
    --arg metadata_application_ci_run_id "${GITHUB_RUN_ID}" \
    --arg metadata_application_ci_run_number "${GITHUB_RUN_NUMBER}" \
    --arg metadata_application_ci_run_attempt "${GITHUB_RUN_ATTEMPT}" \
    --arg metadata_application_ci_workflow_name "${GITHUB_WORKFLOW}" \
    --arg metadata_application_ci_workflow_ref "${GITHUB_WORKFLOW_REF}" \
    --argjson metadata_terraform_git "${metadata_terraform_git}" \
    --arg metadata_action_path "${GITHUB_ACTION_PATH}" \
    --arg metadata_action_ref "${GITHUB_ACTION_REF}" \
    '{
      application: {
        git: $metadata_application_git,
        ci: {
          actor: {
            id: $metadata_application_ci_actor_id,
            name: $metadata_application_ci_actor_name,
          },
          job_id: $metadata_application_ci_job,
          run: {
            id: $metadata_application_ci_run_id,
            number: $metadata_application_ci_run_number,
            attempt: $metadata_application_ci_run_attempt,
          },
          workflow: {
            name: $metadata_application_ci_workflow_name,
            ref: $metadata_application_ci_workflow_ref,
          }
        },
      },
      terraform: {
        git: $metadata_terraform_git,
      },
      action: {
        path: $metadata_action_path,
        git: {
          ref: $metadata_action_ref,
        },
      },
    }' \
    > "${descriptor_directory}/metadata.json" || {
    rc=$?
    echo "[ERROR] Cannot create metadata file '${descriptor_directory}/metadata.json'" >&2
    return $rc
  }

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[INFO] Dry run, replace git write by printing files"

    pushd "${descriptor_directory}" >/dev/null 2>&1 || {
      rc=$?
      echo "[ERROR] Cannot switch to descriptor directory '${descriptor_directory}'" >&2
      return $rc
    }
    local files=()
    files=( $(find . -type f) ) || {
      rc=$?
      echo "[ERROR] Cannot list files in descriptor directory '${descriptor_directory}'" >&2
      return $rc
    }
    local maxlength=0
    local file=''
    for file in "${files[@]}"; do
      [[ ${#file} > ${maxlength} ]] && maxlength=${#file}
    done
    local pad200='--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------'
    local pad="$(cut -c1-${maxlength} <<<"${pad200}")"
    for file in "${files[@]}"; do
      printf -- "------- %-${maxlength}s -------\n" "${file}" &&
      cat "${file}" &&
      echo &&
      printf -- "--------%s--------\n" "${pad}" &&
      true || return $?
    done

    return 0
  else
    echo "[INFO] Git write"
    git.repo.descriptor add . || {
      rc=$?
      echo "[ERROR] Cannot 'git add' descriptor directory '${descriptor_directory}'" >&2
      return $rc
    }
    local author_name=''
    local author_email=''
    local author_source=''
    if [[ ! -z "${GITHUB_ACTOR_ID}" ]]; then
      author_source='environment' &&
      author_name="${GITHUB_ACTOR:-unknown}" &&
      author_email="${GITHUB_ACTOR_ID}+${author_name}@users.noreply.github.com"
    else
      author_source='git' &&
      author_name="$(git.repo.application show --format='%an' --no-patch)" &&
      author_email="$(git.repo.application show --format='%ae' --no-patch)" &&
      true || {
        rc=$?
        echo "[ERROR] Cannot get application Git author name and email" >&2
        return $rc
      }
    fi
    echo "[INFO]    author (${author_source}): name='${author_name}'   email='${author_email}'"
    GIT_COMMITTER_NAME="${author_name}" GIT_COMMITTER_EMAIL="${author_email}" \
    git.repo.descriptor commit \
      --allow-empty \
      --author "${author_name} <${author_email}>" \
      --message "Deploy ${FINALCAD_ENVIRONMENT} ${FINALCAD_REGION_FRIENDLY} ${application_name}" \
    || {
      rc=$?
      echo "[ERROR] Cannot commit descriptor directory '${descriptor_directory}'" >&2
      return $rc
    }

    git.repo.descriptor pull --rebase && git.repo.descriptor push; local status=$?
    if [[ ${status} != 0 ]]; then
      local retry=0
      for retry in {1..60}; do
        printf "[WARN] Cannot 'git push' descriptor directory '${descriptor_directory}', retrying in 2 seconds (Attempt: #%d)\n" "${retry}" >&2
        sleep 2
        git.repo.descriptor pull --rebase && git.repo.descriptor push; status=$?
        [[ ${status} != 0 ]] || break
      done
    fi
    if [[ ${status} != 0 ]]; then
      echo "[ERROR] Cannot 'git push' descriptor directory '${descriptor_directory}'" >&2
      return ${status}
    fi

    return 0
  fi
}

main "$@"
