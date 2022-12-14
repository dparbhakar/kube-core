#!/bin/bash
set -eou pipefail

## Header Start

# Current Script
currentScript=${BASH_SOURCE[0]}
currentScriptPath="$( cd "$( dirname "${currentScript}" )" >/dev/null 2>&1 && pwd )"
currentScriptShortPath=$(echo "${currentScriptPath}" | awk '{split($0, a, "/scripts/"); print a[2]}')

# Cluster Config
if [[ ! -z $(find ./cluster-config.yaml 2> /dev/null) ]]; then
    clusterConfigPath=$(echo ./cluster-config.yaml | head -n 1 | xargs realpath 2> /dev/null)
else
    clusterConfigPath=$(eval find ./$(printf "{$(echo %{1..7}q,)}" | sed 's/ /\.\.\//g') -maxdepth 1 -name cluster-config.yaml | head -n 1 | xargs realpath 2> /dev/null) || true
fi
if [[ -z "${clusterConfigPath}" ]] ; then
    echo "Stopping ${currentScript}"
    echo "This script requires to be in a cluster context, but cluster-config.yaml not found in parent directories"
    exit 0
fi

clusterConfigDirPath=$(dirname ${clusterConfigPath} | xargs realpath)
helmfilePath="${clusterConfigDirPath}/helmfile.yaml"
tmpFolder="${clusterConfigDirPath}/.kube-core/.tmp"

# Cluster Scripts
if [[ ! -z $(find ${currentScriptPath}/scripts-config.yaml 2> /dev/null) ]]; then
    scriptsConfigPath=$(echo ${currentScriptPath}/scripts-config.yaml | head -n 1 | xargs realpath 2> /dev/null)
else
    scriptsConfigPath=$(eval find "${currentScriptPath}"/$(printf "{$(echo %{1..7}q,)}" | sed 's/ /\.\.\//g') -maxdepth 1 -name scripts-config.yaml | head -n 1 | xargs realpath)
fi
scriptsConfigDirPath=$(dirname ${scriptsConfigPath} | xargs realpath)

defaultClusterConfigPath=${scriptsConfigDirPath}/default-cluster-config.yaml
corePath=$(echo ${scriptsConfigDirPath}/.. | xargs realpath)
coreTmpFolder="${corePath}/.kube-core/.tmp"

# Loading scripts
eval "$(${scriptsConfigDirPath}/src/includes.sh)"

# Loading default-cluster-config.yaml
clusterConfigVars=$(parse_yaml ${defaultClusterConfigPath})
clusterConfigVars=$(echo "${clusterConfigVars}" | sed "s|\./|${clusterConfigDirPath}/|")
eval "${clusterConfigVars}"

# Loading cluster-config.yaml
clusterConfigVars=$(parse_yaml ${clusterConfigPath})
clusterConfigVars=$(echo "${clusterConfigVars}" | sed "s|\./|${clusterConfigDirPath}/|")
eval "${clusterConfigVars}"

# Loading scripts-config.yaml
paths=$(parse_yaml ${scriptsConfigPath})
absolutePaths=$(echo "${paths}" | sed "s|\./|${scriptsConfigDirPath}/|")
eval "${absolutePaths}"

check_requirements
prepare_workspace
check_context "${cluster_config_context}"
# check_args "$@"
## Header End


sourceBranch=${1:-"develop"}
targetBranch=${2:-"${sourceBranch}"}
workBranch=${3:-"gitops/update-${sourceBranch}"}
commitMessage=${4:-"gitops: Regen (auto)"}

# Checking out the branch
cd ${clusterConfigDirPath}

log_info "Source branch: ${sourceBranch}"
log_info "Target branch: ${targetBranch}"
log_info "Work branch: ${workBranch}"

log_info "Checking out the target branch: ${targetBranch}"
git checkout ${targetBranch} || true

log_info "Fetching and pulling target branch: ${targetBranch}"
git fetch -a || true
git pull origin ${targetBranch} || true

# log "Checking out ${workBranch}"
# git checkout -b ${workBranch} || true
# git pull origin ${workBranch} || true

# log "Rebasing ${workBranch} on ${targetBranch}"
# git rebase ${targetBranch}

# log "Merging ${sourceBranch} on ${workBranch}"
# git merge ${sourceBranch}

# log "Pushing changes & Creating PR..."
# git push --set-upstream origin ${workBranch} -o merge_request.create -o merge_request.target=${targetBranch}


log_info "Checking if work branch already exists: origin/${workBranch}"
if git rev-parse --quiet --verify origin/${workBranch}; then
    if [[ "${workBranch}" != "${targetBranch}" ]]; then
        log_error "Branch already exists, this case is not handled. Aborting!"
        exit 1
    fi
    # log_warn "Deleting branch and rebuilding !"
    # log_warn "This part should be updated to handle rebase instead of delete/recreate !"

    # log_info "Deleting ${workBranch}"
    # git push origin :${workBranch}

    # log_info "Checking out ${workBranch}"
    # git checkout --track origin/${workBranch} || true

    # log_info "Rebasing ${workBranch} on ${targetBranch}"
    # git rebase ${targetBranch}

    # log_info "Merging ${sourceBranch} on ${workBranch}"
    # git merge ${sourceBranch}
fi


    log_info "Creating work branch: ${workBranch}"

    log_info "Checking out ${workBranch}"
    git checkout -b ${workBranch} || true

    log_info "Pushing and setting upstream: ${workBranch}"
    git push -u origin ${workBranch} || true
    # git branch --set-upstream-to=origin/${workBranch} ${workBranch} || true
    # git pull origin ${workBranch} || true

cd -

somethingChanged="false"


cd ${clusterConfigDirPath}
gitStatus=$(git status --porcelain ${config_path})
if [[ ! -z "${gitStatus}" ]]; then
  somethingChanged="true"
fi
cd -

if [[ "${somethingChanged}" == "true" ]]; then
    cd ${clusterConfigDirPath}

    log "Changes detected in config !"
    echo "${gitStatus}"

    log "Adding config files..."
    git add ${config_path}

    log "Committing..."
    git commit -m "${commitMessage}"

    log "Pushing changes & Updating PR..."
    git pull origin ${workBranch} || true
    git push --set-upstream origin ${workBranch} -o merge_request.create -o merge_request.target=${targetBranch}

    cd -
else
    log "No changes detected in config !"

    # TODO: See how to keep a clean git (delete the branch if we did nothing )
    # Requires to implement git checks on all the repo, not only gitops config as it is now
    #
    # cd ${clusterConfigDirPath}
    # if git rev-parse --quiet --verify origin/${workBranch}; then
    #   echo "WARNING: Deleting branch: ${workBranch}"
    #   echo "WARNING: This is because we create the branch first and then check for changes to push"
    #   echo "WARNING: This logic may change in the future"

    #   log "Deleting ${workBranch}"
    #   git push origin :${workBranch} || true
    # fi
    # cd -

fi
