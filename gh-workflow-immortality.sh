#!/bin/bash
# gh-workflow-immortality.sh
# Keeps cronjob based triggers of GitHub workflows alive.
#
# Copyright (C) 2022  Daniel Rudolf <www.daniel-rudolf.de>
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

VERSION="1.0.0"
BUILD="20230119"

set -eu -o pipefail

APP_NAME="$(basename "${BASH_SOURCE[0]}")"

print_usage() {
    echo "Usage:"
    echo "  $APP_NAME [[--owner] [--collaborator] [--member]|--all] \\"
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

gh_api() {
    local METHOD="${1:-GET}"
    local ENDPOINT="${2:-/}"
    local JQ_FILTER="${3:-.}"

    local CURL_HEADERS=()
    CURL_HEADERS+=( -H "Accept: application/vnd.github+json" )
    [ -z "${GITHUB_TOKEN:-}" ] || CURL_HEADERS=( -H "Authorization: Bearer $GITHUB_TOKEN" )
    CURL_HEADERS+=( -H "X-GitHub-Api-Version: 2022-11-28" )

    ENDPOINT="${ENDPOINT##/}"

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

    # print result
    [ -z "$RESULT" ] || echo "$RESULT"
}

gh_api_repo() {
    local REPO="$1"

    local JSON RETURN_CODE
    JSON="$(gh_api "GET" "/repos/$REPO")"
    RETURN_CODE=$?

    if [ $RETURN_CODE -eq 0 ] && [ -n "$JSON" ]; then
        jq -r '.full_name' <<< "$JSON"
    fi

    return $RETURN_CODE
}

gh_api_repos() {
    local JSON RETURN_CODE
    JSON="$(gh_api "GET" "$@")"
    RETURN_CODE=$?

    if [ $RETURN_CODE -eq 0 ] && [ -n "$JSON" ]; then
        jq -r '.[]|select((.fork or .archived or .disabled)|not).full_name' <<< "$JSON"
    fi

    return $RETURN_CODE
}

gh_api_workflows() {
    local REPO="$1"
    local STATE="${2:-}"

    local JSON RETURN_CODE
    JSON="$(gh_api "GET" "/repos/$REPO/actions/workflows" '.workflows')"
    RETURN_CODE=$?

    if [ $RETURN_CODE -eq 0 ] && [ -n "$JSON" ]; then
        if [ -n "$STATE" ]; then
            jq -r --arg STATE "$STATE" '.[]|select(.state == $STATE).path|split("/")|last' <<< "$JSON"
        else
            jq -r '.[].path|split("/")|last' <<< "$JSON"
        fi
    fi

    return $RETURN_CODE
}

# check dependencies
if [ ! -x "$(which curl)" ]; then
    echo "Missing required script dependency: curl" >&2
    exit 1
fi

if [ ! -x "$(which jq)" ]; then
    echo "Missing required script dependency: jq" >&2
    exit 1
fi

# convert env variables to options
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

# parse options
REPOS=()
DRY_RUN=
EXIT_CODE=0

while [ $# -gt 0 ]; do
    case "$1" in
        "--help")
            print_usage
            echo
            echo "Makes scheduled GitHub workflows immortal by force enabling disabled workflows."
            echo "GitHub will suspend scheduled triggers of GitHub workflows of repositories that"
            echo "didn't receive any activity within the past 60 days. This small script simply"
            echo "iterates all your GitHub repositories and force enables your workflows, so that"
            echo "the workflow's inactivity counter is reset."
            echo
            echo "Repository options:"
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
            echo "  --help              display this help and exit"
            echo "  --version           output version information and exit"
            echo
            echo "Environment variables:"
            echo "  GITHUB_TOKEN        uses the given GitHub personal access token"
            echo "  OWNER_REPOS         passing 'true' enables '--owner'"
            echo "  COLLABORATOR_REPOS  passing 'true' enables '--collaborator'"
            echo "  MEMBER_REPOS        passing 'true' enables '--member'"
            echo "  REPOS_USERS         line separated list of GitHub users for '--user'"
            echo "  REPOS_ORGS          line separated list of GitHub organizations for '--org'"
            echo "  REPOS               line separated list of 'REPOSITORY' arguments"
            echo
            echo "You want to learn more about \`gh-workflow-immortality\`? Visit us on GitHub!"
            echo "Please don't hesitate to ask your questions, or to report any issues found."
            echo "Visit us at <https://github.com/PhrozenByte/gh-workflow-immortality>."
            exit 0
            ;;

        "--version")
            echo "gh-workflow-immortality.sh $VERSION (build $BUILD)"
            echo
            echo "Copyright (C) 2022  Daniel Rudolf"
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

        "--all"|"--owner"|"--collaborator"|"--member")
            case "$1" in
                "--all")          AFFILIATION="owner,collaborator,organization_member" ;;
                "--owner")        AFFILIATION="owner" ;;
                "--collaborator") AFFILIATION="collaborator" ;;
                "--member")       AFFILIATION="organization_member" ;;
            esac
            shift

            # load repos of authenticated user
            GH_USER_REPOS="$(gh_api_repos "/user/repos?affiliation=$AFFILIATION")"
            if [ -z "$GH_USER_REPOS" ]; then
                echo "Failed to load GitHub repositories of authenticated user" >&2
                exit 1
            fi

            readarray -t -O "${#REPOS[@]}" REPOS <<< "$GH_USER_REPOS"
            ;;

        "--user")
            if [ -z "${2:-}" ]; then
                echo "Missing required argument 'USER' for option '--user'" >&2
                exit 1
            fi

            GH_USER="$2"
            shift 2

            # load public (!) repos of given user
            GH_USER_REPOS="$(gh_api_repos "/users/$GH_USER/repos" || { EXIT_CODE=1; true; })"
            if [ -z "$GH_USER_REPOS" ]; then
                echo "Failed to load public GitHub repositories of user: $GH_USER" >&2
                exit 1
            fi

            readarray -t -O "${#REPOS[@]}" REPOS <<< "$GH_USER_REPOS"
            ;;

        "--org")
            if [ -z "${2:-}" ]; then
                echo "Missing required argument 'ORGANIZATION' for option '--org'" >&2
                exit 1
            fi

            GH_ORG="$2"
            shift 2

            # load repos of given organization
            GH_ORG_REPOS="$(gh_api_repos "/orgs/$GH_ORG/repos" || { EXIT_CODE=1; true; })"
            if [ -z "$GH_ORG_REPOS" ]; then
                echo "Failed to load GitHub repositories of organization: $GH_ORG" >&2
                exit 1
            fi

            readarray -t -O "${#REPOS[@]}" REPOS <<< "$GH_ORG_REPOS"
            ;;

        *)
            if [[ ! "$1" == */* ]]; then
                echo "Invalid argument: $1" >&2
                exit 1
            fi

            GH_REPO="$1"
            shift

            # load given repo (primarily to check whether the repo exists)
            GH_REPO_FULL="$(gh_api_repo "$GH_REPO" || { EXIT_CODE=1; true; })"
            if [ -z "$GH_REPO_FULL" ]; then
                echo "Failed to load GitHub repository: $GH_REPO" >&2
                exit 1
            fi

            REPOS+=( "$GH_REPO_FULL" )
            ;;
    esac
done

# nothing to do
if [ ${#REPOS[@]} -eq 0 ]; then
    print_usage >&2
    exit 1
fi

# enable all workflows of the requested repos
if [ -n "$DRY_RUN" ]; then
    echo "Warning: This is a dry run, no GitHub workflows will be enabled..." >&2
fi

for REPO in "${REPOS[@]}"; do
    readarray -t WORKFLOWS_ALIVE < <(gh_api_workflows "$REPO" "active")
    readarray -t WORKFLOWS_DEAD < <(gh_api_workflows "$REPO" "disabled_inactivity")

    echo "GitHub repository '$REPO': ${#WORKFLOWS_ALIVE[@]} alive and ${#WORKFLOWS_DEAD[@]} dead workflows"

    # enable still active workflows
    for WORKFLOW in "${WORKFLOWS_ALIVE[@]}"; do
        echo "- Enabling still active workflow: $WORKFLOW"

        if [ -z "$DRY_RUN" ]; then
            gh_api "PUT" "/repos/$REPO/actions/workflows/$WORKFLOW/enable" || { EXIT_CODE=1; true; }
        fi
    done

    # enable dead workflows
    for WORKFLOW in "${WORKFLOWS_DEAD[@]}"; do
        echo "- Enabling dead workflow: $WORKFLOW"

        if [ -z "$DRY_RUN" ]; then
            gh_api "PUT" "/repos/$REPO/actions/workflows/$WORKFLOW/enable" || { EXIT_CODE=1; true; }
        fi
    done
done

exit $EXIT_CODE
