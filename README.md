GitHub Workflow Immortality
===========================

This GitHub action resp. the [`gh-workflow-immortality.sh` script](gh-workflow-immortality.sh) makes scheduled GitHub workflows immortal by force enabling workflows.

GitHub will suspend scheduled triggers of GitHub workflows of public repositories that didn't receive any activity within the past 60 days. The scheduled triggers no longer run and you'll see the following error:

> This scheduled workflow is disabled because there hasn't been activity in this repository for at least 60 days.

The `gh-workflow-immortality.sh` script simply iterates all your GitHub repositories and force enables your workflows, so that the workflow's inactivity counter is reset. Your scheduled triggers will run indefinitely and your workflows won't ever get suspended by GitHub for inactivity (they are "immortal"). The script will re-enable workflows that were previously disabled due to inactivity, but not workflows that were disabled manually.

The script was written to run with [GNU Bash](https://www.gnu.org/software/bash/). It requires the [`sed`](https://sed.sourceforge.io/), [`awk`](https://linux.die.net/man/1/awk), [`curl`](https://curl.se/), and [`jq`](https://jqlang.github.io/jq/) command line tools to be installed.

Made with :heart: by [Daniel Rudolf](https://www.daniel-rudolf.de/) ([@PhrozenByte](https://github.com/PhrozenByte)). GitHub Workflow Immortality is free and open source software, released under the terms of the [MIT license](LICENSE).

## How to use

You can either run the `gh-workflow-immortality.sh` script manually, or use the GitHub action. No matter what, you must [create a personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token). This is also true when using the GitHub action, because GitHub's automatically created `GITHUB_TOKEN` secret lacks the required permissions.

You can use both fine-grained personal access tokens, and classic personal access tokens. If you choose to use classic personal access tokens, you must enable the "workflow" scope, which also implies the very potent "repo" scope. Thus it's better to use fine-grained personal access tokens when possible: The only repository permission required is the "Actions" permission with both read and write access. You can even limit the fine-grained personal access token to the repositories you really need. Please note that with fine-grained personal access tokens you need a token per GitHub user and GitHub organization. Don't forget to choose a suitable expiration date and to renew your personal access tokens accordingly.

Please note that `gh-workflow-immortality.sh` intentionally excludes forked, archived, and disabled repositories. Even though forked repositories can indeed use scheduled triggers for GitHub workflows, we expect them not to require immortality and are thus excluded by default. If you require the GitHub workflows of a forked repository to be immortal, either specify it using the `repos` options (when using the GitHub action) resp. pass it as command line argument (when running the script manually), or enable the `include_forks` option (when using the GitHub action) resp. pass the `--forks` command line option (when running the script manually). This won't work for archived and disabled repositories though, because they can't have active GitHub workflows. Please also note that `gh-workflow-immortality.sh` will exclude dynamic workflows without a YAML config file in the repo's `.github/workflows/` directory (e.g. the default GitHub Pages workflow), because they don't use scheduled triggers.

`gh-workflow-immortality.sh` will respect GitHub's [REST API rate limiting](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api?apiVersion=2022-11-28). If the limit was reached, the script will bail and tell you when to try again. Since it's practically impossible to pass the limit just with `gh-workflow-immortality.sh`, you should consider running the script at a time with fewer requests from your other applications using the GitHub API. If this isn't possibly, consider running the script multiple times at different times with a subset of repos.

### Using the GitHub action

Simply create a new GitHub workflow like the following and incorporate this GitHub action as its only step:

```yaml
name: GitHub Workflow Immortality

on:
  schedule:
    # run once a month on the first day of the month at 00:20 UTC
    - cron: '20 0 1 * *'
  workflow_dispatch: {}

jobs:
  keepalive:
    name: GitHub Workflow Immortality

    runs-on: ubuntu-latest
    permissions: {}

    steps:
      - name: Keep cronjob based triggers of GitHub workflows alive
        uses: PhrozenByte/gh-workflow-immortality@v1
        with:
          secret: ${{ secrets.PERSONAL_ACCESS_TOKEN }}
          repos: ${{ github.repository }}
```

This example GitHub workflow will run once a month on the first day of the month at 00:20 UTC. It will keep all workflows of the containing GitHub repository alive. Running the workflow once a month is sufficient. Don't forget to [create an encrypted secret](https://docs.github.com/en/actions/security-guides/encrypted-secrets#creating-encrypted-secrets-for-a-repository) (the example expects a secret named `PERSONAL_ACCESS_TOKEN`) with the personal access token you've created earlier (see above).

You can create an "immortality workflow" per repository, per user, per organization, or however you please, simply use the options below to specify the list of GitHub repositories whose workflows should be kept alive. Since your immortality workflow will use a scheduled trigger to run, you must make sure to include it in this list - otherwise GitHub might suspend it for inactivity. You can use the `${{ github.repository }}` variable to get the name of the repository including the immortality workflow.

The GitHub action will accept the following options:

| Option               | Description                                                                                                                       | Default | Required |
|----------------------|-----------------------------------------------------------------------------------------------------------------------------------|---------|----------|
| `secret`             | Personal access token of the executing GitHub user (see above)                                                                    | None    | Yes      |
| `include_forks`      | Also includes forks when loading repositories; either `true` or `false`                                                           | `false` | No       |
| `owner_repos`        | Loads all repositories of the authenticated GitHub user (includes both public and private repositories); either `true` or `false` | `false` | No       |
| `collaborator_repos` | Loads all repositories of which the authenticated GitHub user is a collaborator of; either `true` or `false`                      | `false` | No       |
| `member_repos`       | Loads all repositories of organizations of which the authenticated GitHub user is a member of; either `true` or `false`           | `false` | No       |
| `users`              | Loads all public repositories of the given GitHub users; expects a line separated list of GitHub user names                       | `""`    | No       |
| `orgs`               | Loads all repositories of the given GitHub organizations; expects a line separated list of GitHub organization names              | `""`    | No       |
| `repos`              | Loads the given repositories; expects a line separated list of GitHub repositories, e.g. `PhrozenByte/gh-workflow-immortality`    | `""`    | No       |

Even though none of `owner_repos`, `collaborator_repos`, `member_repos`, `users`, `orgs`, and `repos` is mandatory, the options given must match at least one GitHub repository. Otherwise your GitHub workflow will fail.

### Run script manually

The GitHub action is no more than a wrapper for the `gh-workflow-immortality.sh` script. `gh-workflow-immortality.sh` is just an ordinary Bash script you can run locally on your machine. Simply download the script and check its help:

```console
$ ./gh-workflow-immortality.sh --help
Usage:
  gh-workflow-immortality.sh [--forks] [[--owner] [--collaborator] [--member]|--all] \
    [--user USER]... [--org ORGANIZATION]... [REPOSITORY]...

Makes scheduled GitHub workflows immortal by force enabling workflows. GitHub
will suspend scheduled triggers of GitHub workflows of repositories that didn't
receive any activity within the past 60 days. This small script simply iterates
all your GitHub repositories and force enables your workflows, so that the
workflow's inactivity counter is reset.

Repository options:
  --forks             also loads forked repositories (otherwise excluded)
  --owner             loads all repositories of the authenticated GitHub user
                        (includes both public and private repositories)
  --collaborator      loads all repositories of which the authenticated GitHub
                        user is a collaborator of
  --member            loads all repositories of organizations of which the
                        authenticated GitHub user is a member of
  --all               same as '--owner', '--collaborator', and '--member'
  --user USER         loads all public repositories of the given GitHub user
  --org ORGANIZATION  loads all repositories of the given GitHub organization
  REPOSITORY          loads a single repository, no matter its status

Application options:
  --dry-run           don't actually enable any workflows
  --verbose           print a list of issued GitHub API requests
  --help              display this help and exit
  --version           output version information and exit

Environment variables:
  GITHUB_TOKEN        uses the given GitHub personal access token
  INCLUDE_FORKS       passing 'true' enables '--forks'
  OWNER_REPOS         passing 'true' enables '--owner'
  COLLABORATOR_REPOS  passing 'true' enables '--collaborator'
  MEMBER_REPOS        passing 'true' enables '--member'
  REPOS_USERS         line separated list of GitHub users for '--user'
  REPOS_ORGS          line separated list of GitHub organizations for '--org'
  REPOS               line separated list of 'REPOSITORY' arguments

You want to learn more about `gh-workflow-immortality`? Visit us on GitHub!
Please don't hesitate to ask your questions, or to report any issues found.
Check out <https://github.com/PhrozenByte/gh-workflow-immortality>.
```

For the script to work you must set the `GITHUB_TOKEN` environment variable - otherwise you'll see "Bad credentials" errors. Create a personal access token as described above and pass it as `GITHUB_TOKEN` environment variable. To keep all workflows of all of your own GitHub repositories alive, try the following:

```console
$ export GITHUB_TOKEN=my_personal_access_token
$ ./gh-workflow-immortality.sh --owner
GitHub repository 'PhrozenByte/gh-workflow-immortality': 0 alive and 0 dead workflows
```
