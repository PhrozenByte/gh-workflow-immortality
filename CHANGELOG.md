Changelog of GitHub Workflow Immortality
========================================

### Version 1.1.3
Released: 2025-08-24

* [[#3]](https://github.com/PhrozenByte/gh-workflow-immortality/pull/3) Trim environment variables before usage to support GitHub Action variables [[85f28bb]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/85f28bb)
* Various small improvements [[febd188]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/febd188) [[031c085]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/031c085)

### Version 1.1.2
Released: 2025-05-06

* Properly handle HTTP redirects and partial GitHub API responses [[eff45ae]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/eff45ae)
* Check and document `awk` script dependency [[176fb51]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/176fb51)

### Version 1.1.1
Released: 2025-03-04

* Fix usage of 'REPO' env variable [[a55e781]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/a55e7812491ec2fd8e8a047e7af9790f4ef0de53)
* Various small improvements [[6a65ea0]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/6a65ea076da34c7d4990ddb7d9db558cbf32477f)

### Version 1.1.0
Released: 2025-03-04

* Refactor functions to use return variables instead [[a58ce23]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/a58ce230acc45e2d7434eb85d61282d1b11a37f0)
* Add `--verbose` option to print a list of issued GitHub API requests [[f6c8bd3]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/f6c8bd39c2cbdb3b58ba211db2d8c34c0cbb3f1f)
* Respect GitHub's API rate limit [[5630517]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/56305170000d0bb8d2cf40e2bf4e807f6c9eb641)
* Add `--forks` option to also load forked repositories [[6cbccc4]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/6cbccc4917f4f3286b1d577083ffb70ec441a93f)
* [[#1]](https://github.com/PhrozenByte/gh-workflow-immortality/issues/1) Exclude workflows not matching '.github/workflows/*' [[a274dce]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/a274dce7f5ffc7820c54dc305d0c39e9b5e3741f)
* Various small improvements [[fd10aa4]](https://github.com/PhrozenByte/gh-workflow-immortality/commit/fd10aa441c755e4c72b23a306c26c0633fe187df)

### Version 1.0.0
Released: 2023-01-19

* Initial public release
