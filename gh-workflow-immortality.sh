#!/bin/bash
# gh-workflow-immortality.sh
# Keeps cronjob based triggers of GitHub workflows alive.
#
# Copyright (C) 2022-2025  Daniel Rudolf <www.daniel-rudolf.de>
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

VERSION="1.1.1"
BUILD="20250304"

set -eu -o pipefail
export LC_ALL=C

APP_NAME="$(basename "${BASH_SOURCE[0]}")"
EXIT_CODE=0

# check script dependencies
if [ ! -x "$(which sed)" ]; then
    echo "Missing required script dependency: sed" >&2
    exit 1
fi

if [ ! -x "$(which curl)" ]; then
    echo "Missing required script dependency: curl" >&2
    exit 1
fi

if [ ! -x "$(which jq)" ]; then
    echo "Missing required script dependency: jq" >&2
    exit 1
fi

# convert env variables to options
if [ "${INCLUDE_FORKS:-false}" == "true" ]; then
    set -- --forks "$@"
fi
if [ "${OWNER_REPOS:-false}" == "true" ]; then
    set -- --owner "$@"
fi
if [ "${COLLABORATOR_REPOS:-false}" == "true" ]; then
    set -- --collaborator "$@"
fi
if [ "${MEMBER_REPOS:-false}" == "true" ]; then
    set -- --member "$@"
fi
if [ -n "${REPOS_USERS:-}" ]; then
    while IFS= read -r REPOS_USER; do
        if [ -n "$REPOS_USER" ]; then
            set -- --user "$REPOS_USER" "$@"
        fi
    done < <(printf '%s\n' "$REPOS_USERS")
fi
if [ -n "${REPOS_ORGS:-}" ]; then
    while IFS= read -r REPOS_ORG; do
        if [ -n "$REPOS_ORG" ]; then
            set -- --org "$REPOS_ORG" "$@"
        fi
    done < <(printf '%s\n' "$REPOS_ORGS")
fi
if [ -n "${REPOS:-}" ]; then
    while IFS= read -r REPO; do
        if [ -n "$REPO" ]; then
            set -- "$@" "$REPO"
        fi
    done < <(printf '%s\n' "$REPOS")
fi

# helper functions
print_usage() {
    echo "Usage:"
    echo "  $APP_NAME [--forks] [[--owner] [--collaborator] [--member]|--all] \\"
    echo "    [--user USER]... [--org ORGANIZATION]... [REPOSITORY]..."
}

__curl() {
    local RESPONSE="$(curl -sSL -i "$@")"
    local RETURN_CODE=$?

    local HEADERS="$(sed -ne '1,/^\r$/{s/\r$//p}' <<< "$RESPONSE")"
    local BODY="$(sed -e '1,/^\r$/d' <<< "$RESPONSE")"

    local STATUS_CODE="$(sed -ne '1{s#^HTTP/[0-9.]* \([0-9]*\)\( .*\)\?$#\1#p}' <<< "$HEADERS")"
    if [ -z "$STATUS_CODE" ] || (( $STATUS_CODE < 100 )) || (( $STATUS_CODE >= 300 )); then
        [ $RETURN_CODE -ne 0 ] || RETURN_CODE=22

        local STATUS_STRING="$(sed -ne '1{s#^HTTP/[0-9.]* \(.*\)$#\1#p}' <<< "$HEADERS")"
        echo "curl: (22) The requested URL '${@: -1}' returned error: $STATUS_STRING" >&2
        printf '%s\n' "$BODY" >&2
    fi

    printf '%s\n\n%s\n' "$HEADERS" "$BODY"
    return $RETURN_CODE
}

# GitHub API helper function
declare API_RESULT=

gh_api() {
    local METHOD="${1:-GET}"
    local ENDPOINT="${2:-/}"
    local JQ_FILTER="${3:-.}"

    local CURL_HEADERS=()
    CURL_HEADERS+=( -H "Accept: application/vnd.github+json" )
    [ -z "${GITHUB_TOKEN:-}" ] || CURL_HEADERS=( -H "Authorization: Bearer $GITHUB_TOKEN" )
    CURL_HEADERS+=( -H "X-GitHub-Api-Version: 2022-11-28" )

    ENDPOINT="${ENDPOINT##/}"

    # reset API result
    API_RESULT=

    # print API call in verbose mode
    if [ "$VERBOSE" == "y" ]; then
        echo + "$METHOD https://api.github.com/$ENDPOINT" >&2
    fi

    # check rate limit
    if [ "$ENDPOINT" != "rate_limit" ]; then
        if (( $RATELIMIT_REMAINING == 0 )); then
            echo "curl: (67) GitHub API rate limit exceeded: You must wait till $RATELIMIT_RESET" >&2
            return 67
        fi

        ((RATELIMIT_REMAINING--))
    fi

    # send HTTP request
    local RESPONSE HEADERS RESULT

    RESPONSE="$(__curl "${CURL_HEADERS[@]}" -X "$METHOD" \
        "https://api.github.com/$ENDPOINT")"
    [ $? -eq 0 ] || return 1

    HEADERS="$(sed -e '/^$/q' <<< "$RESPONSE")"
    RESULT="$(sed -e '1,/^$/d' <<< "$RESPONSE")"

    # run jq filter (verifies JSON and prepares it for pagination)
    RESULT="$(jq "$JQ_FILTER" <<< "$RESULT")"
    [ $? -eq 0 ] || return 1

    # send additional HTTP requests to fetch all pages
    local PAGE_COUNT="$(sed -ne 's/^Link: .*<.*[?&]page=\([0-9]*\)>; rel="last".*/\1/Ip' <<< "$HEADERS")"
    if [ -n "$PAGE_COUNT" ] && (( $PAGE_COUNT > 0 )); then
        local PAGE_PARAM="$(awk '{print (/?/ ? "&" : "?")}' <<< "$ENDPOINT")page="
        local PAGE PAGE_RESULT

        for (( PAGE=2 ; PAGE <= PAGE_COUNT ; PAGE++ )); do
            # send HTTP request for nth page
            if [ "$VERBOSE" == "y" ]; then
                echo + "$METHOD https://api.github.com/$ENDPOINT$PAGE_PARAM$PAGE" >&2
            fi

            PAGE_RESULT="$(__curl "${CURL_HEADERS[@]}" -X "$METHOD" \
                "https://api.github.com/$ENDPOINT$PAGE_PARAM$PAGE")"
            [ $? -eq 0 ] || return 1

            # run jq filter (verifies JSON and prepares it for pagination)
            PAGE_RESULT="$(sed -e '1,/^$/d' <<< "$PAGE_RESULT" | jq "$JQ_FILTER")"
            [ $? -eq 0 ] || return 1

            # merge JSON results
            RESULT="$(jq -s 'add' <<< "$RESULT$PAGE_RESULT")"
        done
    fi

    # return result
    API_RESULT="$RESULT"
}

# GitHub repo loader functions
declare -a REPOS=()

load_repo() {
    gh_api "GET" "/repos/$1"
    [ -n "$API_RESULT" ] || return 1

    REPOS+=( "$(jq -r '.full_name' <<< "$API_RESULT")" )
}

load_repos() {
    gh_api "GET" "$@"
    [ -n "$API_RESULT" ] || return 1

    local __RESULT
    if [ -z "$FORKS" ]; then
        __RESULT="$(jq -r '.[]|select((.fork or .archived or .disabled)|not).full_name' <<< "$API_RESULT")"
    else
        __RESULT="$(jq -r '.[]|select((.archived or .disabled)|not).full_name' <<< "$API_RESULT")"
    fi

    [ -z "$__RESULT" ] || readarray -t -O "${#REPOS[@]}" REPOS <<< "$__RESULT"
}

# GitHub workflow loader functions
declare -a WORKFLOWS_ALIVE=()
declare -a WORKFLOWS_DEAD=()

load_workflows() {
    WORKFLOWS_ALIVE=()
    WORKFLOWS_DEAD=()

    gh_api "GET" "/repos/$1/actions/workflows" '.workflows'
    [ -n "$API_RESULT" ] || return 1

    local __RESULT_ALIVE="$(jq -r --arg STATE "active" '.[]|select(.state == $STATE).path' <<< "$API_RESULT")"
    __RESULT_ALIVE="$(sed -ne 's#^\.github/workflows/\(.*\)$#\1#p' <<< "$__RESULT_ALIVE")"
    [ -z "$__RESULT_ALIVE" ] || readarray -t WORKFLOWS_ALIVE <<< "$__RESULT_ALIVE"

    local __RESULT_DEAD="$(jq -r --arg STATE "disabled_inactivity" '.[]|select(.state == $STATE).path' <<< "$API_RESULT")"
    __RESULT_DEAD="$(sed -ne 's#^\.github/workflows/\(.*\)$#\1#p' <<< "$__RESULT_DEAD")"
    [ -z "$__RESULT_DEAD" ] || readarray -t WORKFLOWS_DEAD <<< "$__RESULT_DEAD"
}

# parse script options
FORKS=
GH_AFFILIATIONS=()
GH_USERS=()
GH_ORGS=()
GH_REPOS=()
DRY_RUN=
VERBOSE=

while [ $# -gt 0 ]; do
    case "$1" in
        "--help")
            print_usage
            echo
            echo "Makes scheduled GitHub workflows immortal by force enabling workflows. GitHub"
            echo "will suspend scheduled triggers of GitHub workflows of repositories that didn't"
            echo "receive any activity within the past 60 days. This small script simply iterates"
            echo "all your GitHub repositories and force enables your workflows, so that the"
            echo "workflow's inactivity counter is reset."
            echo
            echo "Repository options:"
            echo "  --forks             also loads forked repositories (otherwise excluded)"
            echo "  --owner             loads all repositories of the authenticated GitHub user"
            echo "                        (includes both public and private repositories)"
            echo "  --collaborator      loads all repositories of which the authenticated GitHub"
            echo "                        user is a collaborator of"
            echo "  --member            loads all repositories of organizations of which the"
            echo "                        authenticated GitHub user is a member of"
            echo "  --all               same as '--owner', '--collaborator', and '--member'"
            echo "  --user USER         loads all public repositories of the given GitHub user"
            echo "  --org ORGANIZATION  loads all repositories of the given GitHub organization"
            echo "  REPOSITORY          loads a single repository, no matter its status"
            echo
            echo "Application options:"
            echo "  --dry-run           don't actually enable any workflows"
            echo "  --verbose           print a list of issued GitHub API requests"
            echo "  --help              display this help and exit"
            echo "  --version           output version information and exit"
            echo
            echo "Environment variables:"
            echo "  GITHUB_TOKEN        uses the given GitHub personal access token"
            echo "  INCLUDE_FORKS       passing 'true' enables '--forks'"
            echo "  OWNER_REPOS         passing 'true' enables '--owner'"
            echo "  COLLABORATOR_REPOS  passing 'true' enables '--collaborator'"
            echo "  MEMBER_REPOS        passing 'true' enables '--member'"
            echo "  REPOS_USERS         line separated list of GitHub users for '--user'"
            echo "  REPOS_ORGS          line separated list of GitHub organizations for '--org'"
            echo "  REPOS               line separated list of 'REPOSITORY' arguments"
            echo
            echo "You want to learn more about \`gh-workflow-immortality\`? Visit us on GitHub!"
            echo "Please don't hesitate to ask your questions, or to report any issues found."
            echo "Check out <https://github.com/PhrozenByte/gh-workflow-immortality>."
            exit 0
            ;;

        "--version")
            echo "gh-workflow-immortality.sh $VERSION (build $BUILD)"
            echo
            echo "Copyright (C) 2022-2025  Daniel Rudolf"
            echo "This work is licensed under the terms of the MIT license."
            echo "For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>."
            echo
            echo "Written by Daniel Rudolf <https://www.daniel-rudolf.de/>"
            echo "See also: <https://github.com/PhrozenByte/gh-workflow-immortality>"
            exit 0
            ;;

        "--dry-run")
            DRY_RUN="y"
            shift
            ;;

        "--verbose")
            VERBOSE="y"
            shift
            ;;

        "--forks")
            FORKS="y"
            shift
            ;;

        "--all"|"--owner"|"--collaborator"|"--member")
            case "$1" in
                "--all")          GH_AFFILIATIONS+=( "owner,collaborator,organization_member" ) ;;
                "--owner")        GH_AFFILIATIONS+=( "owner" ) ;;
                "--collaborator") GH_AFFILIATIONS+=( "collaborator" ) ;;
                "--member")       GH_AFFILIATIONS+=( "organization_member" ) ;;
            esac
            shift
            ;;

        "--user")
            if [ -z "${2:-}" ]; then
                echo "Missing required argument 'USER' for option '--user'" >&2
                exit 1
            fi

            GH_USERS+=( "$2" )
            shift 2
            ;;

        "--org")
            if [ -z "${2:-}" ]; then
                echo "Missing required argument 'ORGANIZATION' for option '--org'" >&2
                exit 1
            fi

            GH_ORGS+=( "$2" )
            shift 2
            ;;

        *)
            if [[ ! "$1" == */* ]]; then
                echo "Invalid argument: $1" >&2
                exit 1
            fi

            GH_REPOS+=( "$1" )
            shift
            ;;
    esac
done

# check current GitHub API rate limit
gh_api "GET" "/rate_limit" '.resources.core'
RATELIMIT_REMAINING="$(jq -r '.remaining' <<< "$API_RESULT")"
RATELIMIT_RESET="$(date -d "@$(jq -r '.reset' <<< "$API_RESULT")" +'%Y-%m-%d %H:%M:%S %Z')"

if (( $RATELIMIT_REMAINING == 0 )); then
    echo "GitHub API rate limit exceeded: You must wait till $RATELIMIT_RESET" >&2
    exit 1
fi

# load repos
for GH_AFFILIATION in "${GH_AFFILIATIONS[@]}"; do
    echo "Loading GitHub repositories of authenticated user..."
    load_repos "/user/repos?affiliation=$GH_AFFILIATION" \
        || { EXIT_CODE=1; true; }
done

for GH_USER in "${GH_USERS[@]}"; do
    echo "Loading public GitHub repositories of user '$GH_USER'..."
    load_repos "/users/$GH_USER/repos" \
        || { EXIT_CODE=1; true; }
done

for GH_ORG in "${GH_ORGS[@]}"; do
    echo "Loading GitHub repositories of organization '$GH_ORG'..."
    load_repos "/orgs/$GH_ORG/repos" \
        || { EXIT_CODE=1; true; }
done

for GH_REPO in "${GH_REPOS[@]}"; do
    echo "Loading GitHub repository '$GH_REPO'..."
    load_repo "$GH_REPO" \
        || { EXIT_CODE=1; true; }
done

# nothing to do
if [ ${#REPOS[@]} -eq 0 ]; then
    echo "No GitHub repositories found" >&2
    exit 1
fi

# remove duplicate repositories
readarray -t REPOS < <(printf '%s\n' "${REPOS[@]}" | sort -u)

# enable all workflows of the requested repos
if [ -n "$DRY_RUN" ]; then
    echo "Warning: This is a dry run, no GitHub workflows will be enabled..." >&2
fi

for REPO in "${REPOS[@]}"; do
    load_workflows "$REPO" \
        || { EXIT_CODE=1; true; }

    echo "GitHub repository '$REPO': ${#WORKFLOWS_ALIVE[@]} alive and ${#WORKFLOWS_DEAD[@]} dead workflows"

    # enable still active workflows
    for WORKFLOW in "${WORKFLOWS_ALIVE[@]}"; do
        echo "- Enabling still active workflow: $WORKFLOW"

        if [ -z "$DRY_RUN" ]; then
            gh_api "PUT" "/repos/$REPO/actions/workflows/$WORKFLOW/enable" \
                || { EXIT_CODE=1; true; }
        fi
    done

    # enable dead workflows
    for WORKFLOW in "${WORKFLOWS_DEAD[@]}"; do
        echo "- Enabling dead workflow: $WORKFLOW"

        if [ -z "$DRY_RUN" ]; then
            gh_api "PUT" "/repos/$REPO/actions/workflows/$WORKFLOW/enable" \
                || { EXIT_CODE=1; true; }
        fi
    done
done

exit $EXIT_CODE
