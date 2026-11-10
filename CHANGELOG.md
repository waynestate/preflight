# Changelog

All notable changes to Preflight are recorded here. Entries follow
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); released versions
are Git tags.

## Unreleased
- Changed: the docs, agent-ready and deploy kits are Squire 0.10.6 (was 0.10.5 for the deploy kit, Squire a7a40ab of 2026-11-08 for the docs and agent-ready files): the docs builder and agent-ready generator see every file on Docker Desktop mounts, and each heading keeps its "#" link with its last word.
- Changed: the deploy kit is Squire 0.10.7 (was 0.10.6): it ships a `.gitattributes` that pins line endings, so the deploy layer clears PROCTOR's line-ending warnings.
- Changed: the docs, agent-ready and deploy kits are Squire 0.10.6 (was 0.10.5 for the deploy kit; the docs and agent-ready files were Squire a7a40ab, between 0.10.2 and 0.10.3 in name only): the docs builder and agent-ready generator see every file on Docker Desktop mounts, and each heading keeps its "#" link with its last word.
- Fixed: secret detection really blocks now. GitLab's template marks the job allow_failure: true, so dropping the old override left it advisory (pipeline 5392). `.gitlab-ci.yml` sets allow_failure: false on secret_detection, and both check scripts now require it.
- Added: a must-fail fixture for squire-kit. `must-fail-squire-kit` proves the component fails on a kit with a drifted file and on a folder with no .squire.json. Every component that runs as a job now has a must-fail fixture; only `a11y`'s still runs by hand, with no CI job yet.
- Docs: BEST_PRACTICES matches the code before 1.0. The component version line (2.11) is `Enforced` by the contract job, the proctor default command (6.1) is `Checked` on every pipeline, and the counts are real again: ten components in Preflight's own pipeline, eight `working_dir` inputs, ten tags through 0.5.0, four components that take `allow_failure`. The must-fail list names npm-audit and package-publish and says squire-kit still has none, and thirteen finished backlog items are marked Done with the file that proves each. A preflight checklist that finally matches the airplane.
- Site: `assets/stack-env.js` knows Parity, so a pre-production page links Parity's pre-production site and a dev page links its local `site/` folder. Until now Parity, of all parts, was the one link that ignored its environment.
- Changed: Preflight's own secret detection job now blocks the pipeline (a week of green runs since 2026-11-02 ended its advisory spell), and the README badge's alt text counts 14 components like the badge does.
- Site: Parity is out; the party list links its site.
- Deploy kit refreshed to Squire 0.10.5.
- Docs: Parity joins the party. The README cast ("Fifteen on the manifest") and the front page's Departures board carry Parity next to Squire, with its spirit-level mark: the stack's new tool that runs Citadel on your computer (its PHP image, its proxy and MySQL 5.6). 0.1.0 is coming and it has no site yet, so its row links nowhere. Every pilot logs simulator hours before the real runway; now apps can too.
- Changed: refreshed version mentions. BEST_PRACTICES says PROCTOR's and CREED's pipelines include `preflight/proctor@0.5.0` (both pipelines fly 0.5.0; the checklist still read 0.4.0); the dev dependency Pinstripe moves to ^0.3 (locked 0.3.0, was ^0.1 at 0.1.4), and the front page deploy layer requires HELMET ^1.3 (locked 1.3.0, was ^1.2 at 1.2.0).
- Docs: README, the guides, the docs pages, the examples and the front page pin the 0.5.0 tag commit; the Upgrading page and the npm-audit examples name it in place of the full commit SHA placeholder, and the front page placards say "in 0.5.0" and count npm-audit among the components that ship in the tag.
- Docs: the front page's type certificate data sheet is amended to 0.5.0 (the AMDT 0.5.0 stamp, a change bar on php-test's `composer_version` default, now 2.11.1, and a new log of amendments that says in a line what 0.4.0 and 0.5.0 changed), its diff example and those in the README, the components reference, the inputs contract guide and Upgrading read `git diff 0.4.0 0.5.0`, the guide says what that diff shows, the 0.5.0 Upgrading section notes the renovate `dry_run` pattern now on record, the deferred-items note says the contract suite shipped in 0.5.0, and the README checklist art lists all fourteen components in 0.5.0 with npm-audit's row (its components badge reads 14; the art kit closes the list up to 18 units a row so it fits).

## 0.5.0 (2026-11-09)

Tag commit: `60314791565a264e97cb210813ef4f3e76512402` (pin this SHA, with `# 0.5.0` in a trailing comment).

A new component and a probe that boots Apache the way a container runtime does: `npm-audit` fails on npm advisories
at or above `audit_level` (default `high`), the portability job starts each replica with stdio its uid owns and a
session of its own (delete any `start_command` setsid shim in the same change as the bump, or `health` fails), the
proctor job keeps PROCTOR's JSON report as `proctor.json` for Rollcall, and every Composer default is 2.11.1. The
deploy layer moves to Squire's kit 0.10.2, HELMET ^1.2 and PROCTOR ^0.11.

- Docs: the Upgrading page has a 0.5.0 section; the npm-audit guide, the components reference and the README name 0.5.0 as the first tag with npm-audit (their include examples said "the first tag with npm-audit"); the docs home names 0.5.0.
- Docs: MAINTAINING's "Who maintains it" names a role, the stack maintainer, instead of a person, and says to reach them with an issue on git.wayne.edu.
- Changed: the front page deploy layer requires HELMET ^1.2, PROCTOR ^0.11 and CREED ^0.1.8 (locked 1.2.0, 0.11.0 and 0.1.8; were 1.0.1, 0.8.0 and 0.1.7). The fixture app requires PROCTOR ^0.11 (locked 0.11.0, was 0.8.0), so Preflight's own proctor job now runs a PROCTOR that writes `proctor.json` and the artifact keeps it; the fixture still passes every check and its `composer ci`. Preflight's dev tools take Pinstripe 0.1.4 (was 0.1.0), the newest release on Packagist.
- Changed: the deploy kit is Squire 0.10.2 (was 0.10.0), and so is the squire-kit fixture (`tests/squire-kit-fixture`, was 0.5.0): the kit names every image in full (`docker.io/library/...`) and takes the fallback base's Composer from a `COMPOSER_IMAGE` stage, `.squire/php.ini` sets `session.cookie_samesite = Lax`, and the portable image drops `node_modules/` after the frontend build. The fixture also takes the files Squire added since 0.5.0 (Apache hardening, `php-web.ini`, the portable image). `squire init --check` passes on both.
- Docs: the Docker-only commands in the README, MAINTAINING, Local checks and Proof pin the CI image, `composer:2.11.1@sha256:8de2184c...` (they said the floating `composer:2`), the front page's commands and composer-audit placard say `composer:2.11.1`, and the composer-audit pages and template comment stop calling its image `composer:2`.
- Fixed: the portability probe starts each replica the way a container runtime would, so an Apache image (Squire's portable image, WELD) passes with an empty `start_command`. On its own, `buildah run` hands the app root-owned stdout and stderr, which Apache running as the uid cannot reopen (`could not open error log file /proc/self/fd/2`), and starts no session, so Apache's graceful stop signals `buildah-chroot-exec` too, which SIGKILLs the app and failed `sigterm`. Each replica now starts through a launcher that pipes stdout and stderr through `cat` on a pipe the uid owns and execs the app through `setsid`, keeping its pid; it runs the Buildah image's own `bash`, `setsid` and `cat` from its `/usr`, bind-mounted read-only at `/.preflight/usr` for the run, so the app image needs none of them. The checks are unchanged. Remove any `start_command` shim that calls `setsid` (WELD's `exec setsid bash -c '...'`): inside the launcher it forks the app away from the replica's main process and `health` fails. Proof: two new fixture builds in `tests/check-portability.sh`, `reopens-stderr` and `signals-group`, must pass every check and fail on the 0.4.0 probe; WELD's portable image, run locally with WELD's inputs and an empty `start_command`, passes all five of its checks. Docs: the portability page (What the job emulates) and a troubleshooting entry.
- Added: the `npm-audit` component, the front-end half of `composer-audit` (CREED backlog 23, practice 41). It runs `npm audit --omit=dev --audit-level=<audit_level>` on the app's `package-lock.json` in the `eslint` component's Node image and fails at or above the level (default `high`), then prints a full report with dev dependencies that never fails. Inputs: `stage`, `job_name`, `image`, `image_prefix`, `working_dir`, `audit_level` (`low`, `moderate`, `high`, `critical`; CREED's `medium` runs as npm's `moderate`) and `omit_dev` (default `true`). No lock file passes with a "nothing to audit" line; an unreachable registry fails with a message; `--audit=true --offline=false` stop an `.npmrc` from faking a pass. It reads the app's npm cache (fixed key `npm`, `.cache/npm/`, pull only, D-072). Proof: `tests/check-npm-audit-fails.sh` (and its `.ps1` twin), the `tests/npm-audit-fails` lock (lodash 4.17.20, GHSA-35jh-r3h4-6jhm) and `tests/npm-audit-fixtures`, run by the new `must-fail-npm-audit` job; Preflight's pipeline also includes the component on the clean fixture. New docs page: The npm-audit component.
- Added: the proctor job keeps PROCTOR's JSON report as `proctor.json` in its artifact (`paths: [proctor.json]`, `expire_in: 30 days`, still `when: always` next to the Code Quality report), the file Rollcall reads with `ROLLCALL_PROCTOR_SOURCE=gitlab`. A guard adds `--record "$CI_PROJECT_DIR/proctor.json"` only when `proctor_command` is a plain `proctor check` line (no quotes, `$` or shell operators, no `--record` of its own) and the app's PROCTOR lists `--record` in its help (0.11.0 and later); PROCTOR 0.10.0 and older run exactly as before and the runner only warns that `proctor.json` matched no files. The proctor line alone still decides the job. `tests/check-proctor-fails` (sh and ps1) now runs the template's own guard and command line on three fakes: no `--record` (`tests/fixture-app`), a clean one with it (new `tests/proctor-record`) and the must-fail one with it (`tests/proctor-fails`), plus a gate command and a quoted one that must not get the flag.
- Changed: every component default, Preflight's own CI and the docs move from Composer 2.10.3 to 2.11.1 (`composer:2.11.1@sha256:8de2184c...`, the multi-arch list digest; php-test's and proctor's `composer_version` default is `2.11.1`). Composer 2.11.0 fixed GHSA-c968-33g3-wh7p (package names that could escape the vendor directory) and GHSA-fm2w-xgf2-f9fh (inline repository headers written into `composer.lock`), and 2.10.x is no longer maintained. 2.11 removed `source-fallback`; no component sets it, and no component sets `policy.cooldown`. An app that overrides the `image` input (or sets `composer_version`) keeps its own pin and is unaffected.
- Changed: the deploy kit is Squire 0.10.0 (was 0.7.1): release.sh keeps Composer and npm download caches in the app folder and the gate takes SQUIRE_PHP_RUNTIME; the compose file, health.php and .env.squire.example follow the template, and the portable image files are added.
- Added: a must-fail check for composer-audit (`tests/check-composer-audit-fails.sh`, its .ps1 twin, the `must-fail-composer-audit` job and a malware fixture in `tests/audit-fixtures/malware`): Preflight's pipeline now runs the template's own lines and proves a known advisory and a malware-flagged version fail in every `abandoned` mode, an abandoned package fails only in `fail` mode, and a clean app passes. `tests/check-abandoned-input` keeps only its offline half and joins the contract job.
- Changed: every template default and doc pins composer 2.10.3 by one digest (sha256:2cf27542...), the same build the rest of the stack uses; composer-audit's default names 2.10.3 instead of the floating 2 tag.
- Added: a must-fail check for package-publish (`tests/check-package-publish-fails.sh`, its .ps1 twin and the `must-fail-package-publish` job): a non-semver tag and a missing composer.json still stop the release before any registry contact.
- Docs: README, the guides, the docs pages and the examples pin the 0.4.0 tag commit, and the upgrading page has a 0.4.0 section.
- Added: a PHPUnit suite (`tests/ComponentsContractTest.php`, run as `composer test` inside `composer ci`) that parses every template and fails when a component no longer matches `contract/inputs.json`, naming the component and the added, removed or changed input or job and saying a rename is a breaking change; `composer contract:update` rewrites the contract from the templates when the change was made on purpose, and this run records the renovate `dry_run` regex the template already carries.
- Docs: the inputs contract is documented where component users look: a new guide (`docs/guides/inputs-contract.md`, in the docs menu), sections in the README and the components reference, a diff-the-contract step in Upgrading, a link from Install, and a "Type certificate" section on the front page whose data sheet marks the lines 0.4.0 revised; the CONTRACT lamp is live, the "New in" line and the README checklist art speak for 0.4.0, and BEST_PRACTICES marks backlog item 6.1 (the `proctor` default command, now in PROCTOR's and CREED's pipelines) done.

## 0.4.0 (2026-11-08)

Tag commit: `87d9b6fc6b0ed302dd729986525282cd7b567ebd` (pin this SHA, with `# 0.4.0` in a trailing comment).

Two new inputs and a Composer floor: the proctor component's `git_depth` clones the full history so PROCTOR's
override-approver check can read git blame, php-test's `php_advisory_version` runs the next PHP in a job that may fail,
and php-test and proctor refuse a `composer_version` older than 2.9.6. Preflight's own pipeline now proves ten
components fail a bad app (eslint, secret-detection and sbom are new), runs the real PROCTOR, and the deploy layer moves
to Squire's kit 0.7.1 and HELMET ^1.0.

- Docs: BEST_PRACTICES 3.3 is tagged `Partly`, not `Not yet`: PROCTOR's `ci-pipelines` check reads `.gitlab-ci.yml` and `.github/workflows/ci.yml`, and the entry names the four flags still missing.
- Added: a must-fail fixture for the secret-detection component (`tests/secret-detection-clean`, `tests/check-secret-detection-fails.sh` and its Windows twin, the `must-fail-secret-detection` job): Preflight's pipeline proves Gitleaks fails on a token in the app's code, skips vendor/ and node_modules/, and redacts the value.
- Added: a must-fail fixture for the sbom component (`tests/sbom-clean`, `tests/sbom-fails`, `tests/check-sbom-fails.sh` and its Windows twin, the `must-fail-sbom` job): Preflight's pipeline proves the job fails when Composer fails and that the SBOM leaves dev packages out.
- Added: a must-fail fixture for the eslint component (`tests/eslint-fails`, `tests/check-eslint-fails.sh` and its Windows twin, the `must-fail-eslint` job): Preflight's pipeline proves the job fails on an ESLint error and passes a clean app.
- Changed: php-test's and proctor's `composer_version` refuses a Composer older than 2.9.6 (the floor with the 2026 security fixes); the pattern is held by `tests/check-composer-floor.sh` (and its Windows twin, `tests/check-composer-floor.ps1`) in the contract job.
- Changed: Preflight's own pipeline runs the real PROCTOR (`waynestate/proctor` ^0.8 in the fixture app) on the proctor component's default command, instead of a fake that printed an empty report; the fake stays only for the offline `check-proctor-fails` wiring check.
- Added: the proctor component's `git_depth` input (default `"0"`, the full history), so PROCTOR's override-approver check can read git blame on every override line instead of reporting could-not-run past the 20-commit default clone.
- Added: php-test's php_advisory_version input runs one more PHP version (a release candidate) in a separate job that may fail, so an app hears about the next PHP before it is supported (BEST_PRACTICES 6.4).
- Fixed: the contract check resolves job names that contain the job_name input (php-test-advisory) and skips hidden template jobs, so main is green again.
- Fixed: the component-version check follows `extends:` to a hidden base job, so php-test's jobs pass when their script comes from `.php-test-base`.
- Docs: a deprecation and removal policy for components (docs/guides/deprecation.md): tags never move, one release of notice, six months before removal, and the Catalog toggle stays on while any version is pinned.
- Changed: the deploy layer runs Squire's kit 0.7.1 (was 0.6.0): `.squire/php.ini` no longer sets the deprecated `session.sid_*` lines, web requests get a `disable_functions` list and Apache hardening (`.squire/php-web.ini`, `.squire/apache-hardening.conf`), and opcache gets production settings with `SQUIRE_OPCACHE_VALIDATE` as the one switch.
- Docs: the docs home footer names 0.3.1 (it still said 0.3.0).
- Changed: the front page deploy layer requires HELMET ^1.0 (lock at 1.0.1, was 0.4.0), like the rest of the stack; its shared front controller already runs on HELMET 1.0 in Squire, Sourdough and Pinstripe.
- Docs: README, the guides, the docs pages and the examples pin the 0.3.1 tag commit, and the upgrading page has a 0.3.1 section.

## 0.3.1 (2026-11-08)

Tag commit: `b90323b5823287a7840095d0d5f0682aaeedf327` (pin this SHA, with `# 0.3.1` in a trailing comment).

Fixed CI cache keys (D-072): every component that installs packages caches under a fixed key instead of a lock-file
hash, and saves its cache even when the job fails, so a lock change or a dropped GitHub download refetches only what
is missing. Inputs and job names are unchanged, so moving a pin from 0.3.0 is a one-line change.

- Changed: every component saves its dependency cache even when the job fails (when: always), so a retry after a dropped download fetches only what is missing (D-072).
- Fixed: README, BEST_PRACTICES 4.8 and the caching guides describe the fixed cache keys (D-072).
- Changed: php-test, phpstan, pint, proctor, sbom and eslint cache under a fixed key per job instead of a lock-file hash (D-072), so a lock change downloads only the packages that changed.
- Fixed: the docs menu closes with Escape and hands focus back to its button (docs kit synced from Squire).
- Fixed: the docs kit's copy button no longer covers the first line of code when it says Copied or Failed: over the code it keeps its resting width and shows a check or a cross when the word does not fit (docs kit synced from Squire).
- Changed: the front page's version chip carries `data-docs-version`, so the docs builder (synced from Squire) keeps it on the docs stamp at every release and `composer docs:check` fails while it is stale.
- Changed: the deploy layer requires PROCTOR ^0.8 (locked 0.8.0).
- Docs: the README, docs, front page and examples pin the 0.3.0 tag's commit SHA, and the GitHub workflow example moves from 0.1.1 to 0.3.0.
- Fixed: the front page said a11y and squire-kit were coming in the next tag; both shipped in 0.2.0. The checklist card gains an eighth check, a11y, which lights the A11Y lamp (it was a hatched "next tag" lamp), the placards add an a11y placard and name the five other components in 0.3.0, and "Deferred items" keeps only the contract suite and site freshness, with no date for the next tag. The README's checklist art is rebuilt to match: nine rows, all thirteen components in 0.3.0, and a components badge that reads 13 (it read 9).
- Fixed: the README art kit (`scripts/readme-art`) reads job names from the `job_name` input every template now uses, puts the stage list on its own line (it ran past the panel), closes up the component list when it grows, and labels the license badge in US spelling.

## 0.3.0 (2026-11-08)

Tag commit: `23038dfe767f6ef60e3b2efca1128f53d9acdff7` (pin this SHA, with `# 0.3.0` in a trailing comment).

- Changed (breaking for apps that pass a proxied `image`): every component whose image comes from Docker Hub (`proctor`, `php-test`, `composer-audit`, `sbom`, `pint`, `phpstan`, `eslint`, `secret-detection`, `package-publish`, `renovate`, `squire-kit`) has a new `image_prefix` input, default `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}`, and pulls `image_prefix/image`, so Docker Hub is asked once and GitLab's Dependency Proxy serves the cached copy. `image` keeps its default and is now the path after the prefix. On a GitLab or group without the proxy, set `image_prefix: docker.io`. An app that passed `image: ${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/...` only to reach the proxy drops that input when it moves to this version. `a11y` (mcr.microsoft.com) and `portability` (quay.io) are unchanged: the proxy serves Docker Hub only. `contract/inputs.json` lists the new input.
- Changed: the front page's deploy layer (`deploy/`) runs Squire's kit 0.6.0 (was 0.5.0): `scripts/release.sh` asks PROCTOR's deploy gate for a go or no-go on each release (a report, not a stop, unless `SQUIRE_PROCTOR=enforce`), and `.env.squire.example` lists the new setting. The layer's pins move to HELMET `^0.4` (locked 0.4.0) and PROCTOR `^0.7` (locked 0.7.0).
- Docs: the Docker commands in the README and docs mount the shared `stack-composer-cache` volume, so Composer downloads are cached between runs.
- Fixed: the README and docs describe the `portability` health check's `Host` as a bare IP address and the port (`Host: <ip>:<port>`) instead of printing a literal private address.
- Fixed: the front page's "Same instance only" caution says git.wayne.edu has an instance runner and the stack's CI runs on it (it said git.wayne.edu had no runner yet), and its cast says Sourdough starts all five app shapes.
- Fixed: `tests/check-sha-pins.ps1` runs again on Windows. PowerShell read `"$rel:"` in its failure message as a scope-qualified variable and refused to parse the script.
- Added: Composer caches on `pint`, `phpstan`, `sbom` (keyed on `composer.lock`) and `squire-kit` (fixed key), and an npm cache on `a11y` (fixed key), the same shape as `php-test`, `proctor` and `eslint` already had.
- Added: `tests/check-dependency-cache` (sh and ps1), run in the `contract` job. It fails when a Docker Hub component skips `image_prefix`, when a component installs Composer or npm packages without a cache, or when Preflight's own `.gitlab-ci.yml` pulls from Docker Hub without the proxy or passes a component an image that already carries it. Preflight's own includes no longer pass `image`.
- Added: docs page Dependency caching (Guides), and an `image_prefix` row in every Docker Hub component's input table.
- Docs: the component pins in the README, the docs, the front page and the Renovate runner example point at 0.3.0, and the upgrading page has the 0.3.0 steps.
- Added: `scripts/a11y.sh --base-url` and `scripts/a11y.ps1 -BaseUrl` (or `A11Y_BASE_URL`) check a running site locally, as the component's `base_url` input does in CI.

## 0.2.0 (2026-11-07)

- Changed (breaking for 0.1.4 includes of `portability`): the `portability` component is one job that runs the six checks of ADR-0010 decision 5 instead of goss. It builds the image with Buildah (vfs storage, chroot isolation: no Docker daemon, no privileged runner, no registry push), boots it twice side by side as an arbitrary uid in group 0 with no capabilities and no passwd entry, and probes it with curl: the strict boot (app root not writable, writable paths writable by group 0, the port variable honored, no writes outside `writable_paths` and `runtime_paths`), then `health` (200 to `Host: 10.1.2.3:<port>`), `env-only` (no `.env` or config cache in the image), `forwarded-headers` (forged `X-Forwarded-*` and identity headers change nothing), `logs` (stdout or stderr, nothing under `logs_path`), `session-hop` (a sign-in survives a hop to the second replica) and `sigterm` (the main process handles SIGTERM and exits within `stop_timeout`). One `portability: <check>: pass|FAIL|skipped` line per check. The probe is `templates/portability/probe.sh`, inlined in the template byte for byte; new contract test `tests/check-portability-inline` (sh and ps1, with a write mode) keeps the two in step.
- Changed: `portability` inputs. `buildah_image` is renamed `image` (same default); the app-image `image` input is gone; `start_command` is optional (empty runs the image's `ENTRYPOINT` and `CMD`); new `job_name` (default `portability`), `build_args`, `runtime_paths`, `port_env`, `env`, `stop_timeout`, `probe_path`, `identity_header`, `session_login_path`, `session_check_path`, `logs_path` and `checks`. `contract/inputs.json` lists the new set and the one job; `tests/check-job-names` now covers `portability`, and `tests/check-image-inputs` has no exemptions left.
- Added: a must-fail proof for `portability`: one fixture app, `tests/portability/app`, built clean and once per flaw (`ARG FLAW`: needs-root, writes-root, fixed-port, host-bound, dotenv, trusts-proxy, file-logs, file-sessions, no-term-handler). `tests/check-portability` (sh, run inside the Buildah image, and a ps1 wrapper that runs it with Docker and `seccomp=unconfined`, never `--privileged`) passes only when the clean build passes and each flaw fails the check it targets. Preflight's pipeline includes the component on the clean fixture and runs the check as `must-fail-portability`.
- Removed: `templates/portability/goss.yaml`, the goss download, the registry push and the `tests/portability/good`, `bad-needs-root` and `bad-writes-root` fixtures.
- Changed: The canonical repository is git.wayne.edu (ADR-0021); docs, links and package metadata no longer point at the archived nougat copy.
- Added: must-fail fixtures for the php-test, phpstan and pint components: `tests/php-test-fails` carries a failing test, `tests/phpstan-fails` carries a type error, and `tests/pint-fails` is not formatted to the standard, while the clean case in `tests/fixture-app` passes all three; new checks `tests/check-php-test-fails`, `tests/check-phpstan-fails` and `tests/check-pint-fails` (sh and ps1) assert each template keeps the job line that lets the tool's exit code be the job result, then run the component's own commands from its template, in the component's own image, against both cases, and pass only when the clean case passes and the bad case fails with the expected finding. The `must-fail-php-test` and `must-fail-phpstan-pint` jobs run them in CI, in the templates' own images, and they still run locally with Docker.
- Added: the `squire-kit` component (`templates/squire-kit/template.yml`), which fails the pipeline when a Squire deploy kit drifts from the Squire release its `.squire.json` records. It installs that release from Packagist into a temporary folder (`--no-dev --no-scripts`) and runs `squire init --check` on `working_dir`; exit 0 the kit matches, 1 it drifted, 2 the check could not run. Inputs: `stage`, `job_name`, `image`, `working_dir`, `squire_version` (empty or `x.y.z`) and `allow_failure` (default `false`). It checks the recorded version, so a new Squire never turns main red by itself. Preflight's own pipeline runs it on `tests/squire-kit-fixture`, a kit written by `squire init --target=raw`. New contract test `tests/check-squire-kit` (sh and ps1). New docs page: The squire-kit component.
- Added: the preset's `waynestate/squire` rule runs `postUpgradeTasks`: it installs the new Squire into a folder under `/tmp` and runs `squire update` on the kit folder, so the merge request for a new Squire carries the refreshed kit. The renovate component gains a `squire_kit_tasks` input (boolean, default `false`) that writes the two allowed command patterns into the runner's `config.js` (`allowedCommands`); with it off the merge request bumps the version only and shows an artifact error. No shell executor is turned on. New contract test `tests/check-renovate-squire-kit` (sh and ps1) pins the commands, the patterns and 22 hostile variants they must refuse; `tests/check-renovate-review` no longer forbids `postUpgradeTasks`.
- Fixed: Renovate no longer updates files inside a Squire kit (`docker-compose.squire.yml` and `.squire/**`, outside Squire's own `templates/`). Its digest and tag bumps edited files Squire owns, which left every stack kit drifted from its recorded release and made `squire update` refuse to refresh them. Change those images in Squire's templates instead.
- Added: a must-fail fixture for the proctor component: `tests/proctor-fails` is a fake proctor that prints one blocker finding and exits 1, while the clean case in `tests/fixture-app` prints `[]` and exits 0; new check `tests/check-proctor-fails` (sh and ps1) runs both cases and keeps the template's plain redirect, so the tool's exit code stays the job result, and the contract job runs it.
- Added: the `a11y` component (`templates/a11y/template.yml`), accessibility as a gate with one include. It opens a site's pages in Chromium with Playwright and runs axe-core through `@axe-core/playwright` in light and dark mode at 320 px and 1280 px, and fails on any violation; at 320 px or less it also checks WCAG 1.4.10 Reflow, which axe-core cannot. The default tags are WCAG 2.1 AA (the ADA Title II level); `wcag22aa` adds 2.2 AA. It serves `site_dir` on a local port or checks a running site at `base_url`, takes paths or globs in `pages` (a glob that matches nothing is a configuration error, a missing page fails with HTTP 404), and writes `gl-a11y-junit.xml` (the merge request's test summary) and `gl-a11y-report.json` (every finding, plus the count axe-core left for a person to review). The image is the multi-arch Playwright image pinned by index digest; the playwright npm version comes from its tag, axe-core and @axe-core/playwright are pinned inputs, and the job fails if a different axe-core ran. `allow_failure` (default `false`) lets a site adopt it while fixing its first findings. The checker is `templates/a11y/check.mjs`, inlined in the template; new contract test `tests/check-a11y-inline` (sh and ps1) keeps the two byte for byte, and `tests/check-a11y` (sh and ps1, Docker) proves it passes a clean fixture site and fails a known-bad one with each flaw named (`tests/a11y-fixtures`). Preflight's own pipeline includes it at WCAG 2.2 AA. `renovate/default.json` bumps the two axe-core packages as one group, waiting for review. New docs page: The a11y component.
- Added: a site accessibility gate: `scripts/a11y.sh` on Linux and macOS and `scripts/a11y.ps1` on Windows run the `a11y` component's checker in Docker (same image and versions as the template, so no host browser is needed) on the front page and every docs page at WCAG 2.2 AA, in light and dark mode at 320 px and 1280 px with the reflow check, and fail on any violation; all pages pass clean. Options pick the folder, pages, tags and a report folder. The earlier copy under `tools/a11y/` is gone.
- Added: a secret-detection component (Gitleaks over the checked-out tree with `--redact`, a `gitleaks.json` report artifact uploaded even on failure, `config_path` and `allow_failure` inputs), so every stack repo gets committed-secret scanning from one include line; the first release carrying it is 0.2.0.
- Fixed: the portability component's writable-path checks now run. The `portability-run` job read `writable_paths` through `$([[ inputs.writable_paths ]])`, which GitLab does not interpolate, so the value reached the job's shell as a failing command substitution, the variable came out empty, and no `writable-*` goss check was ever appended; the line now interpolates the input as a literal string. New test `tests/check-input-interpolation` (sh and ps1) fails on any template that keeps a `$([[` form or an `inputs.` reference outside `$[[ ... ]]`.
- Fixed: the proctor and sbom jobs install the app with `--ignore-platform-reqs`. Both only read the app, yet a lock built for an older PHP or one needing gd, oci8 or ldap stopped them before PROCTOR or CycloneDX ran, so the oldest apps got no report. The sbom job also passes `--no-scripts`, so the app's Composer scripts no longer run in it. Found by the 2026-11-05 proof run; `tests/check-proctor-install-flags` (sh and ps1) now checks both lines.
- Added: a public Proof page (`docs/reference/proof.md`, under Reference): the components run against 82 Wayne State applications, what held, what the run caught in Preflight, and what it does not prove. Local checks and the README link to it.
- Added: troubleshooting entries for an install that stops on another PHP or a missing extension, a private package with no credential, and `npm ci` without a `package-lock.json`.
- Security: the front-page deploy layer moves to Symfony 7.4.23 (symfony/http-foundation and symfony/yaml advisories, including CVE-2026-118514).
- Changed: the docs theme carries the hero's sectional chart (its grid and contour rings) faintly under the top of every page, frames the overview's picture of the front page like the hero's instrument, and sets the badges in a row. Dark mode now really is the instrument panel: the kit's dark block had been winning for the page and inline code backgrounds, which left WayneUI's dark green surface everywhere; titles are panel light and the lit green is kept to links, the current page and focus.
- Changed: the docs pages wear the front page's look: its top bar and main menu (Docs marked current), B612 and B612 Mono, the cream chart page, commands on the quickstart's slab with its Copy key, callouts as the handbook's NOTE, CAUTION and WARNING boxes, tables and the pager as flight-plan forms, and the green runway footer; dark mode follows the instrument panel. New `docs/_header.html` and `docs/theme/preflight.css`, named under `theme` in `docs/docs.json`.
- Changed: the docs builder and kit are Squire's 0778fed: the theme hook, callouts, code tabs, task-list checkbox labels (fixes the axe `label` failures on the protection checklist) and a keyboard-reachable scrolling code block.
- Fixed: the contract job's Buildah pin check no longer needs git, which the mikefarah/yq image does not have; when git is missing or fails it scans regular files with find instead, skipping .git, vendor/ and node_modules/.
- Added: a Composer cache on the proctor component, keyed on composer.lock (BEST_PRACTICES 4.8); new test tests/check-proctor-cache.
- Added: every component job prints a `Preflight component <name> <version> (ref <reference>, sha <sha>)` line as its first command, so a job log says which Preflight release produced it; each template declares `spec: component: [name, version, sha, reference]`. New tests `tests/check-component-version.sh` and `tests/check-component-version.ps1`; `tests/check-spec-keys` and the template lint allow `component` under `spec:`.
- Changed: Preflight now needs GitLab 18.7 or later: `spec: component:` is generally available from 18.7, and pipeline creation fails on the unknown key on older instances.
- Added: the docs site at `site/docs/`, built from `docs/` by Squire's shared docs builder (`bin/docs-site.php`), starting with the overview page. New composer scripts: `docs` builds it, `docs:check` fails when it is stale, and `ci` now runs the check.
- Docs: component pins in the README and site examples now point at 0.1.4.
- Changed: the front-page deploy layer pins HELMET ^0.3, PROCTOR ^0.4 and CREED ^0.1 (lock: HELMET 0.3.0, PROCTOR 0.4.0, CREED 0.1.6).
- Changed: the deploy layer sets minimum-stability to stable.
- Changed: phpstan config and memory_limit, pint config and sbom output now carry an input regex (relative paths and PHP sizes only); a value outside it stops the pipeline at creation. New test tests/check-path-input-regex.
- Added: a tag-triggered `release` job in the repository's own pipeline: pushing a protected tag creates the GitLab Release through the Releases API with curl, and the release notes carry the tag's commit SHA so consumers can pin it (BEST_PRACTICES 1.3, 1.6); new test tests/check-release-job.
- Added: a packageRule in `renovate/default.json` that restricts `quay.io/buildah/stable` to `-immutable` tags (regex versioning), so Renovate never moves a pin back to a mutable tag after Red Hat re-pushed one and garbage-collected the old digest; new test tests/check-renovate-buildah.
- Changed: the portability component's `buildah_image` default moves to the immutable tag `quay.io/buildah/stable:v1.43.5-immutable@sha256:7c2b605262748ace2c5c57c5550942d0adad57aec82ede3070927722306c0ffb`; Red Hat re-pushed the plain version tag and garbage-collected the old digest, so pipelines pinned to the mutable tag broke. New test tests/check-buildah-pin.
- Added: an `abandoned` input on the composer-audit component (`fail`, `report` or `ignore`, default `fail`) so an app can relax how `composer audit` treats abandoned packages on purpose; the job now runs `composer audit --locked --abandoned=$[[ inputs.abandoned ]]`. New test tests/check-abandoned-input (and its `.ps1` twin) with the fixtures in tests/audit-fixtures.
- Fixed: the `portability` probe's `sigterm` check no longer fails, now and then, an app that stops at once. It checked whether the main process was still running in two steps (is its status file there, then is it a zombie), and a process reaped between the two read as running, so a clean exit could be reported as "still running 10s after SIGTERM" without any wait. It now reads the status once, takes its verdict from the same check that ended the wait, and no longer prints a stray `/proc/<pid>/cmdline` error when a process ends while the probe looks at it.

## 0.1.4 (2026-11-03)

### Changed

- Changed: the README explains which jobs may be allowed to fail (only `proctor`) and that the contract check rejects global keys; BEST_PRACTICES 2.3 is now Enforced.
- Changed: check-image-inputs allows `portability-build` to take `buildah_image` (the only exemption from 2.10).
- Changed: docs and package metadata name nougat as the canonical repository, with git.wayne.edu and GitHub as read-only mirrors, until git.wayne.edu has CI runners.

### Added

- Added: README example for an advisory job on the next PHP release (a second `php-test` include with `job_name`), and PowerShell forms of the local Docker commands.
- Added: a `job_name` input on every component except `portability` (default is the usual job name), so one project can include a component more than once; `tests/check-job-names` enforces it and `tests/check-contract` resolves the key.
- Added: portability component (Buildah build, arbitrary-uid boot, goss checks, fixtures).
- Added: a Squire kit version rule in `renovate/default.json`: a custom regex manager reads the `version` line of `.squire.json`, and the `waynestate/squire` bump carries the `squire-kit` label and never auto-merges; a person runs `squire update` to refresh the kit files.

### Fixed

- Fixed: the component-rule manager name in `renovate/default.json` (`gitlabci`, matching repository deps), so component version bumps really wait for review instead of auto-merging; the contract test now checks the new rule and the Squire kit rule.
- Fixed: the portability goss health check uses `method: GET`; goss sends the method as written, and a lower-case one makes the server close the connection, so the good fixture failed with EOF.
- Fixed: the portability fixtures make their temp dir mode 0777 and the goss files in it mode 0644, because the app user is not the host user that owns the dir and goss is downloaded into it.

## 0.1.3 (2026-11-03)

### Added

- Added: advisory secret detection in the repository's own pipeline.
- Added: `tests/check-renovate-review.sh` (and its `.ps1` twin), a contract test that keeps the reviewed-bump rules in `renovate/default.json`.
- Added: README "Protection checklist": protected default branch, protected release tags, merge request approvals, `no_one_allowed` pipeline variables and no protected variables in fork pipelines.
- Added: README "Set up (the user does this)": the private runner project, the `RENOVATE_TOKEN` and optional `GITHUB_COM_TOKEN` CI variables, and a pipeline schedule; this repository creates none of them.

### Changed

- Changed: README and examples show SHA pins with the tag in a trailing comment.
- Changed: `renovate/default.json` no longer auto-merges updates inside `templates/**`, `contract/**` and `.gitlab-ci.yml`, or component include version bumps: they carry the `needs-review` label and wait for a person.
- Changed: the deploy layer's Squire kit is refreshed to 0.3.3 (release options can now live in ./.env.squire).
- Changed: the deploy layer's Squire kit is refreshed to 0.3.4 (the local .env.squire file is now git-ignored).
- Documented: running the composer-audit component on a weekly pipeline schedule.
- Documented: the job token allowlist rule and the runner request wording (non-privileged, ephemeral Docker executor).
- Changed: the repository's own pipeline pulls Docker Hub images through the GitLab Dependency Proxy (component defaults are unchanged).
- Changed: the proctor component installs the app with --no-plugins --no-scripts.

### Fixed

- Fixed: stale 0.1.0 and next-tag wording in the best practices, the GitHub example and the checklist art.
- Fixed: the readme art script handles all nine components, including package-publish and renovate.
- Fixed: BEST_PRACTICES 2.2, 2.9 and 6.2 match the templates.
- Fixed: BEST_PRACTICES statements match the repo; README no longer claims Renovate bumps component pins.
- Fixed: the renovate component no longer sets `RENOVATE_TOKEN` and `GITHUB_COM_TOKEN` from themselves in the job `variables:`; on GitLab 19.5 that self-reference arrived as literal text and shadowed the masked project CI/CD variables, so the job now reads both tokens straight from the project.

## 0.1.2 (2026-10-29)

### Added

- Added: agent-ready site (prompt blocks, Markdown twins, llms.txt), from Squire's kit.

### Fixed

- Fixed: stale capability claims in the site and README.

### Changed

- Docs: README.md, MAINTAINING.md and site/index.html pin components at
  `@0.1.1`, and the notes about components arriving in a later tag are gone,
  because 0.1.1 contains every component.
- Changed: the proof page moves to a private site that needs a Wayne State sign-in.
- Changed: project names written as words except acronyms.

## 0.1.1 (2026-10-29)

### Added

- `package-publish` component: publishes a semantic version tag to the
  GitLab group's built-in Composer registry. The job reads the registry
  before publishing, so republishing from the same commit is a no-op and
  republishing from a different commit fails instead of overwriting the
  version.
- `renovate` component and shared preset `renovate/default.json`: Renovate
  runs as a scheduled GitLab pipeline in a private runner project and bumps
  image digests, GitHub action SHAs and package versions across the stack.
  Bumps of `component:` include pins are not covered yet: the preset carries
  no manager for them. Digest, pin and patch/minor updates auto-merge when CI
  is green; majors open a merge request and wait for a person.

### Changed

- PHPStan: `phpstan.neon` now includes Pinstripe's `raw.neon` preset from
  the new `waynestate/pinstripe` dev dependency instead of carrying a hand
  copy of its settings. The repo keeps only its own paths, excluded fixture
  app and PHP version range. Strict rules stay off as before, and
  deprecation checks now run on every analysis.

## 0.1.0 (2026-10-27)

- First tagged release.
