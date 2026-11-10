# Preflight best practices

Status: draft, checked against sources on 2026-10-27, with a second research pass the same day (see "Second pass
(2026-10-27)" near the end). Applies to the Preflight components at the state of the repo today: the latest tag is
0.5.0, and CHANGELOG.md names the release that added each component.

## What this covers

Preflight is a set of GitLab CI/CD components that every stack project and WSU app includes with
`include: component:`. Today it has fourteen: `php-test` (PHP versions through `parallel:matrix`), `composer-audit`, `npm-audit`,
`proctor`, `sbom`, `pint`, `phpstan`, `eslint`, `secret-detection`, `a11y` (the accessibility suite, 6.5),
`portability`, `package-publish`, `renovate` and `squire-kit` (a deploy kit still matches its Squire release). A contract
suite, `contract/inputs.json`, holds the inputs and job names every template promises, and the `contract` job checks it
on every pipeline.

This guide is for two groups:

- **WSU developers** who add Preflight to an app's `.gitlab-ci.yml`.
- **Preflight maintainers** who write, test and release the components.

It covers how to write and release components, how to keep a pipeline safe, and where a shared template can and cannot
force a standard. Each practice says what to do, why, where the idea comes from, and how the stack holds it today.

PHP that has reached end of life is not supported, and Preflight does not test it.

### The four tags

| Tag | Meaning |
|---|---|
| `Enforced` | Code makes the bad outcome impossible, or the build fails. The entry names what. |
| `Checked` | PROCTOR or CI warns or fails. The entry names the check. |
| `Documented` | Written down only. Nothing fails if it is ignored. |
| `Not yet` | A gap. Neither code nor text covers it today. |

Tags come from the Preflight and PROCTOR repos and the stack design documents as read on 2026-10-27. Where a design
document describes something that is not built, the tag is `Documented` or `Not yet`.

### One limit to know first

A component is not a lock. GitLab merges the main `.gitlab-ci.yml` over any included job, so an app can change
`allow_failure`, `script` or `rules` of an included job, or leave the include out. The strong form of "cannot be
skipped", pipeline execution policies, is an Ultimate feature, and git.wayne.edu reports itself as GitLab Community
Edition. Practices 3.1 to 3.3 deal with this.

The second pass confirmed the Community Edition point: the `https://git.wayne.edu/help` page shows the heading "GitLab
Community Edition" and gives no version number. The edition and version matter for this guide, because some features
named below need a recent GitLab (array `options` on inputs needs 19.0, `spec:component` is GA in 18.7, `spec:inputs:rules`
arrived in 18.7). Ask ops for the version before relying on any of them. Pipeline execution policies (Ultimate) and
Code Owners (Premium and Ultimate) were re-checked in the GitLab docs and are not available on Community Edition.

---

## 1. Distributing components

### 1.1 Pin every include to a full commit SHA or a protected release tag
Use a 40-character SHA, or a release tag you control. Never use `~latest`, a branch name or a bare partial version in a
real pipeline.

Why: a tag or branch can move; a SHA cannot.

Second pass: GitLab's component page ranks the reference types as commit SHA first, then tag, then branch, then
`~latest` or a partial version, and says to use `~latest` only if you want the absolute latest at all times. Its pipeline
security page says to use "a specific ref" such as a commit hash or protected tag, and to avoid versionless includes.
Prior art: the Drupal Association's shared GitLab templates use semantic version tags, plus a moving `default-ref` tag
that the maintainers move to roll out a vetted release. Projects that want stability pin a specific version.

Sources: [GitLab: CI/CD components, versions](https://docs.gitlab.com/ci/components/);
[GitLab: pipeline security, includes](https://docs.gitlab.com/ci/pipeline_security/);
[OpenSSF Scorecard: Pinned-Dependencies](https://github.com/ossf/scorecard/blob/main/docs/checks.md).

**How the stack holds it: Documented.** The README and examples now show SHA pins with the tag in a comment, and Renovate proposes the bumps for review. PROCTOR's own
`.gitlab-ci.yml` pins a full SHA, with a comment against `~latest`. Nothing checks an app's includes.

### 1.2 Protect the component project's default branch and release tags
Only maintainers merge to the default branch, force pushes are blocked, and release tags are protected.

Why: whoever can move what a pinned tag points to controls every pipeline that includes it.

Correction (second pass): the first pass credited the GitLab components page for "protect release tags". That page
recommends protected branches, merge requests, 2FA, signed commits and approvals for maintainers. It does not mention
tag protection. Tag protection comes from GitLab's protected tags page, which says protection prevents "accidental update
or deletion" and limits who may create a tag. That page does not say a protected tag can never be moved, so a SHA is
still the only fixed reference (see 1.6).

Sources: [GitLab: components, security](https://docs.gitlab.com/ci/components/);
[GitLab: protected tags](https://docs.gitlab.com/user/project/protected_tags/);
[GitLab: protected branches](https://docs.gitlab.com/user/project/repository/branches/protected/);
[OpenSSF Scorecard: Branch-Protection](https://github.com/ossf/scorecard/blob/main/docs/checks.md).

**How the stack holds it: Documented.** The README's "Protection checklist" lists the settings as a task list:
protect the default branch with a required merge request, protect the release tags so only maintainers can create or
move one, set merge request approvals to at least one, set "Minimum role to use pipeline variables" to
`no_one_allowed`, and keep fork pipelines away from protected variables. Nothing in the repo checks the settings:
they are project settings Preflight cannot create or verify, and a read-only token drift report was considered and
left out on purpose.

### 1.3 Publish to the CI/CD Catalog with a semantic-version tag and a release job
The catalog needs a root `README.md`, a project description, components under `templates/`, and a job that uses the
`release` keyword on a tag. Run the tests before the release job.

Why: the catalog gives typed discovery and lets consumers pin an exact or partial version.

Sources: [GitLab: components, publishing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** The layout is right (`templates/<name>/template.yml`, a README), and the tag-triggered `release` job now exists in this repository's own pipeline: pushing a protected tag creates the GitLab Release with the commit SHA in its notes, after the test and audit stages. The Catalog entry still depends on the first tag run, because the release job has not run for a tag yet.
The README examples pin the latest release (0.5.0) for every component and the GitHub workflow.

### 1.4 Keep inputs and job names stable inside a major version
Do not rename an input, change its type, or rename a job in a minor release.

Why: consumers pin a range such as `@1`, and a rename breaks them without warning.

Sources: [GitLab: components, partial semver](https://docs.gitlab.com/ci/components/);
[GitLab: component examples, versioning](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Checked.** `contract/inputs.json` lists each component's inputs (name, type, default) and
job names. `tests/ComponentsContractTest.php` (PHPUnit, run by `composer test` inside `composer ci`) parses every
template and fails on any drift, naming the component and the added, removed or changed key; `tests/check-contract.sh`
and `tests/check-contract.ps1` make the same comparison in the `contract` job. `tests/check-contract-fails.sh` (and
its `.ps1` twin) and `testTheComparisonCatchesAChangedDefaultAndARename` prove both comparisons fail on a changed
default and a renamed input. A rename or a changed default is a breaking change: bump the major version and say so in
`CHANGELOG.md`. When the change was made on purpose,
`composer contract:update` rewrites the contract from the templates.

### 1.5 Know that components work only inside one GitLab instance
A component can be used only by projects on the same instance. Another instance needs a mirror.

Why: it decides where Preflight and the apps that use it must live.

Sources: [GitLab: components, cross-instance access](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** The README has a "Same instance only" section. git.wayne.edu now has an
instance runner, and the stack's CI runs on it. Every product in the stack still strongly recommends a
git.wayne.edu instance runner, so that capacity stays there.

### 1.6 Assume a tag can move, and give consumers the SHA
Publish the commit SHA next to every release tag in the release notes. Tell apps to pin the SHA and use the tag only as a
label in a comment.

Why: in March 2025 the `tj-actions/changed-files` GitHub Action was compromised (CVE-2025-30066). Reports say an attacker
with a maintainer's token re-pointed existing version tags to a malicious commit, so every workflow that pinned a tag
ran it. Workflows that pinned a full commit SHA were reported as unaffected unless they bumped to a bad SHA in the
exposure window. The same pattern showed up in PHP in 2026: Packagist's own write-up says most recent attacks used taken-over
GitHub accounts or stolen tokens to change or add tags. GitLab is not GitHub, but the lesson is the same.

Sources: [StepSecurity: tj-actions breach](https://www.stepsecurity.io/blog/when-changed-files-changed-everything-our-black-hat-2025-presentation-on-the-tj-actions-supply-chain-breach);
[Orca: tj-actions/changed-files compromised](https://orca.security/resources/blog/github-action-tj-actions-changed-files-compromised/);
[Packagist: supply chain security update](https://blog.packagist.com/an-update-on-composer-packagist-supply-chain-security).
The tj-actions details above come from search summaries of these pages and the NVD record could not be read in this
pass, so treat the exact counts and dates as unverified.

**How the stack holds it: Documented.** Ten tags, `0.1.0` through `0.5.0`, exist, and MAINTAINING.md documents the release process,
including recording the tag's commit SHA in the CHANGELOG when a tag is cut. The tag-triggered `release` job now puts the
commit SHA in the GitLab Release notes on every tag (the first run is still to come), so new releases carry the SHA from
the start. Apps still pin the tag in their component includes, and nothing checks an app's includes.

### 1.7 Give consumers a reviewed way to bump their pins
A pin that nobody updates freezes security fixes. Offer a scheduled merge request or a bot that proposes new SHAs and new
image digests, and have a person review each one.

Why: pinning trades surprise for staleness. Composer itself shipped security releases on 2026-04, 2026-06-04,
2026-07-01 and 2026-08-27 (see 4.9), so a frozen tool is a known risk.

Sources: [Renovate: Docker digest pinning](https://docs.renovatebot.com/docker/);
[Renovate: GitLab CI include manager](https://docs.renovatebot.com/modules/manager/gitlabci-include/).
Renovate's Docker docs confirm it can pin a digest, keep the tag for readability and open a pull request when the digest
changes. Its GitLab include page lists only the `gitlab-tags` datasource and does not say whether it updates
`component:` includes or SHA pins. That is unverified, so test it against a sample app before promising it.

**How the stack holds it: Documented.** The README's "Updating image pins" section says pins change only through a reviewed merge request,
and the shared preset `renovate/default.json` provides the tooling for image digests, GitHub action SHAs and packages. Whether Renovate
bumps `component:` includes is unverified: the preset carries no manager for them.

### 1.8 Say how a component is retired
Before removing a component or turning off its Catalog toggle, announce it and keep the old tag working for a stated period.

Why: GitLab says that turning off the CI/CD Catalog resource toggle deletes the Catalog metadata for the project and its
published versions, and that republishing needs a new release. The docs do not say whether `component:` includes pinned
by SHA keep working afterwards. That is unverified.

Sources: [GitLab: components, unpublishing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** `docs/guides/deprecation.md` sets the policy: tags never move, one release of deprecation notice, 6 months before a component is removed, and the Catalog toggle stays on while any version is pinned.

---

## 2. Writing a component

### 2.1 Declare typed inputs with a description and a default
Every setting is an input with a type, a description and a sensible default. Replace a whole YAML value with an input so
it keeps its type (an array feeds `parallel:matrix`, a boolean feeds `allow_failure`).

Why: GitLab refuses undeclared inputs and checks types when the pipeline is created, and inputs cannot change during
the run.

Sources: [GitLab: CI/CD inputs](https://docs.gitlab.com/ci/inputs/);
[GitLab: component examples](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Enforced.** All fourteen templates use `spec:inputs` with types, descriptions and defaults.
GitLab rejects a wrong type or an unknown input at pipeline creation. The first pipeline, back when Preflight had
three components, passed all six jobs with the array input.

Second pass, limits to design around: GitLab's inputs page says a pipeline can take up to 20 inputs (it does not say
whether that counts per include, so check on the real instance before adding many), a string that uses an input must be
under 1 MB, and an interpolation block must be under 1 KB. GitLab also recommends inputs over pipeline variables since 17.7
(see 3.5).

### 2.2 Constrain inputs that reach a shell
Use `options` or `regex` on inputs that are placed into `script` lines. Quote them. Do not rely on escaping.

Why: GitLab calls `posix_escape` best effort and says to use `type`, `regex` or `options` for untrusted values.

Sources: [GitLab: CI/CD inputs, guidance](https://docs.gitlab.com/ci/inputs/);
[OWASP CICD-SEC-4 Poisoned Pipeline Execution](https://owasp.org/www-project-top-10-ci-cd-security-risks/).

**How the stack holds it: Documented.** Every `working_dir` input (eight components carry one) is constrained by
`regex: '^(\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$'` and quoted at its only use, `cd "$[[ inputs.working_dir ]]"`. The two
`composer_version` inputs match `^2\.(9\.([6-9]|[1-9][0-9]+)|[1-9][0-9]+\.[0-9]+)$` (2.9.6 or later), and
`renovate`'s `dry_run` matches `^(null|lookup|full)$`. The four
path-like inputs that reach a shell line are now constrained too: `phpstan` `config` and `pint` `config` and `sbom`
`output` match `^[A-Za-z0-9_-][A-Za-z0-9._/-]*$` (a relative path only), and `phpstan` `memory_limit` matches
`^(-1|[0-9]+[KkMmGg]?)$` (a PHP size such as `1G`); `tests/check-path-input-regex.sh` (and its `.ps1` twin) pins both
regex lines and checks sample values on every pipeline. Still free by design are `test_command` (php-test),
`proctor_command` (proctor) and `eslint_args` (eslint): they are arbitrary commands or arguments, so a path regex would
only pretend to constrain them. The values come from the app's own author, so the risk is low, but `proctor_command` is
also how an app could drop `--policy` or add `--today`.

Second pass: the GitLab inputs page was re-read and the first pass is right. It says "Do not rely on `posix_escape` for
security purposes with untrusted input values". It recommends `number` and `boolean` types, `regex` and `options` for
untrusted values. New point: from GitLab 19.0 an array input with `options` makes the pipeline refuse to start if any
array item is not in the list. That would let `php_versions` accept only versions the policy lists (see 6.2), but it
depends on the instance running 19.0 or later, which is unknown. GitLab's pipeline security page also says to avoid
variables in container references because they can be changed to point at a malicious image. `php-test` builds its image
from the matrix variable (`php:${PHP_VERSION}-cli-trixie`). The value comes from the `php_versions` input, so the risk is low,
but constraining that input closes it.

### 2.3 Keep settings in the job, and give each component one job purpose
Put `image` and other keys inside the job, not at the top level of the template. One component does one thing.

Why: global keys leak into the consuming pipeline.

Sources: [GitLab: component examples](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Enforced.** All fourteen templates follow it. `tests/check-contract.sh` fails on any top-level
key that is not a job named in `contract/inputs.json`, so a template cannot add a global key. The README's "Which jobs
may be allowed to fail" explains why `proctor`, `secret-detection`, `a11y` and `squire-kit` take `allow_failure`, and
why the audit jobs take none.

### 2.4 Make the stage an input
Consumers have their own stage lists.

Why: a hard-coded stage that the app does not define stops the pipeline from being created.

Sources: [GitLab: component examples, configurable stages](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Enforced.** Each template takes `stage` as an input with default `test`. The self-test in
`.gitlab-ci.yml` places `composer-audit` in a second stage through the input.

### 2.5 Let one project include a component more than once
Build job names from an input so two includes (for example two `working_dir` values in a monorepo) do not collide.

Why: two jobs with the same name merge into one.

Sources: [GitLab: component examples, dynamic job names](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Enforced.** Every component takes a `job_name` input whose default is the
usual job name (`proctor`, `php-test`, `composer-audit`, `sbom`, `pint`, `phpstan`, `eslint`, `secret-detection`, `a11y`,
`package-publish`, `renovate`, `squire-kit`, `portability`), and `tests/check-job-names.sh` fails if a template builds its job key any other way. `tests/check-contract.sh`
resolves the key to the default, so the job names stay stable inside a major version.

### 2.6 Offer a way to weaken a gate only where it is meant
`composer-audit` and `npm-audit` have no `allow_failure` input, on purpose. `proctor`, `secret-detection`, `a11y` and
`squire-kit` have one, for adoption.

Why: every switch is a way to ship around the standard.

Sources: [GitLab: CI/CD YAML, `allow_failure`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Documented.** Comments in the `composer-audit` and `npm-audit` templates say advisories must
fail. The README's "Which jobs may be allowed to fail" names the four components that take `allow_failure` and why each
may fail during adoption, and an app can override any of them anyway (see 3.1).

### 2.7 Pass the tool's exit code through
Redirect output to the report file; do not pipe it through `tee`, which would hide the exit code.

Why: the job result must be the tool's result.

Sources: [GitLab: CI/CD YAML, `allow_failure` and job results](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Enforced.** The `proctor` template redirects with `>` and a comment records why. The
self-test cannot prove it, because the fixture's `bin/proctor` always exits 0 (see 7.2).

### 2.8 Upload reports even when the job fails
Declare the report artifact with `when: always`. Use GitLab's native report types.

Why: the merge request should show the findings of the run that failed.

Sources: [GitLab: Code Quality](https://docs.gitlab.com/ci/testing/code_quality/);
[GitLab: CI/CD YAML, `artifacts:when`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Enforced.** The `proctor` template sets `artifacts: when: always` and
`reports: codequality: gl-code-quality-report.json`, and keeps PROCTOR's JSON report as `proctor.json` (`paths:`,
30 days) for Rollcall when the app's PROCTOR has `check --record` (0.11.0 and later). Code Quality is shown in the merge request Reports tab on every
tier; the pipeline tab needs Premium and the diff view needs Ultimate.

Second pass: tiers re-checked and correct. One addition: GitLab deprecated its built-in CodeClimate-based Code Quality
template in 17.3 and plans to remove it in 19.0, and prefers importing a tool's own report. Preflight uses the report
artifact, not the template, so it is not affected. The report must be a single JSON array with no byte order mark, and
each entry needs `description`, `check_name`, `fingerprint`, `location.path` (no leading `./`), a line number and a
`severity` of `info`, `minor`, `major`, `critical` or `blocker`. PROCTOR's output should be tested against those rules.

### 2.9 Set a timeout, and let superseded pipelines be canceled
Give each job a `timeout` and `interruptible: true` where a newer push makes the old run pointless.

Why: a hung `apt-get` or `composer install` holds a runner, and runners are the scarce part of a shared instance.
GitLab's `interruptible` defaults to `false`. The `timeout` keyword cannot be set in `default`, so each job needs its own.
A job timeout cannot exceed the runner's timeout.

Sources: [GitLab: CI/CD YAML, `timeout` and `interruptible`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Documented.** All fourteen templates set `interruptible: true` and a `timeout` of their own:
`10m` for pint and phpstan, `10 minutes` for squire-kit and npm-audit, `15m` for eslint, `30 minutes` for composer-audit, package-publish, php-test, proctor,
sbom, secret-detection, a11y and portability, and `1 hour` for renovate. What stays open is the cancellation half: whether a superseded pipeline is actually
canceled still needs `workflow:auto_cancel` in the app's own file, which a component cannot force (see 3.1).

### 2.10 Make every job image an input
`proctor` and `composer-audit` already take `image`. `php-test` builds its image from `php_versions` and has no way to
swap the image family.

Why: GitLab's component examples expose the image as an input, and the stack needs to move to WSU-controlled or
Citadel-matching images later (see 4.2) without a new major version.

Sources: [GitLab: component examples, inputs for image versions](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Checked.** Every component takes `image` as an input, and every job's `image:` is
`$[[ inputs.image ]]`. `php-test`'s default is `php:${PHP_VERSION}-cli-trixie`: the literal `${PHP_VERSION}`
survives input interpolation, and GitLab expands it in the image at job time, so the matrix keeps working.
`tests/check-image-inputs.sh` (and its `.ps1` twin) fail if a job's `image:` stops being an input or a default
`php:` tag loses its Debian release name. `tests/check-image-inputs-fails.sh` (and its `.ps1` twin) proves it: a
hard-coded php-test image and a default tag without the Debian release both make the guard fail.

There are no exemptions: `portability` builds and runs the app image inside its own job, so its `image` input is the
Buildah image the job runs in, like every other component's.

A component whose image comes from Docker Hub also takes `image_prefix` (default
`${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}`, the group's Dependency Proxy), and its job's `image:` is
`$[[ inputs.image_prefix ]]/$[[ inputs.image ]]`, so pulls are cached on GitLab instead of counted against Docker Hub's
limit. `tests/check-dependency-cache.sh` (and its `.ps1` twin) fail if one skips the prefix or installs packages
without a cache. See [Dependency caching](docs/guides/dependency-caching.md).

### 2.11 Print which component version ran
Use `spec:component` and `$[[ component.sha ]]` or `$[[ component.version ]]` to write the component's own version into
the job log.

Why: when a job misbehaves, the log should say which release of Preflight produced it. GitLab's docs say `spec:component`
exposes `name`, `sha`, `version` and `reference`, was beta in 18.6 and became GA in 18.7.

Sources: [GitLab: components, `spec:component`](https://docs.gitlab.com/ci/components/);
[GitLab: component examples, versioning with component context](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Enforced.** All fourteen templates declare `component: [name, version, sha, reference]` under
`spec:` and print the `Preflight component <name> <version> (ref <reference>, sha <sha>)` line as the first command of
every job (for example `templates/proctor/template.yml:75`), and `tests/check-component-version.sh` (and its `.ps1` twin)
fails the `contract` job if a template drops the declaration or stops printing the line first. The line needs GitLab
18.7 or later; the version on git.wayne.edu is still unconfirmed (see 5.5), but PROCTOR's and CREED's pipelines include
`preflight/proctor@0.5.0`, which carries the declaration, and run on it.

---

## 3. What a shared template cannot force

### 3.1 Say plainly that an app can override, skip or delete an included job
State it in the docs, and measure adoption instead of assuming it.

Why: the main `.gitlab-ci.yml` is merged over included jobs, and an app can simply not include Preflight.

Sources: [GitLab: includes, merge behavior](https://docs.gitlab.com/ci/yaml/includes/);
[GitLab: pipeline execution policies (Ultimate)](https://docs.gitlab.com/user/application_security/policies/pipeline_execution_policies/).

**How the stack holds it: Documented.** The stack's enforcement-points decision names the CI gate as point (c) and Fleet as point (e), which shows
who skips CI. Rollcall reads each app's newest `proctor.json` from the proctor job's artifact
(`ROLLCALL_PROCTOR_SOURCE=gitlab`), but it does not report skipped or weakened pipelines yet.

Prior art (second pass): Drupal's shared GitLab templates, used by more than 2,000 contributed projects at the time of
a December 2025 post, do not force anything. Most jobs are turned off by setting a variable to 0, and projects keep
control of their setup. Drupal's answer to drift is a central `default-ref` tag and strong defaults, not a lock. That
fits what GitLab Community Edition allows.

### 3.2 Review changes to `.gitlab-ci.yml` like code
Require a merge request and a second person for the CI file. Protect the default branch.

Why: CI configuration runs with the repo's credentials, so editing it is a way to run code and read variables.

Sources: [GitLab: CI/CD variables, risks](https://docs.gitlab.com/ci/variables/);
[OWASP CICD-SEC-4 and CICD-SEC-1](https://owasp.org/www-project-top-10-ci-cd-security-risks/);
[GitLab: protected branches](https://docs.gitlab.com/user/project/repository/branches/protected/).

**How the stack holds it: Documented.** Protected branches with required merge requests are available on every tier.
Code owner approval is Premium or Ultimate, so it is not available on Community Edition. The README's "What the
components cannot force" section recommends the settings for app repos: protect the default branch and require a
merge request to change it.

### 3.3 Detect pipelines that skip or weaken Preflight
A check or a fleet report should flag an app with no Preflight include, an unpinned include, `allow_failure: true` on a
gate, or a missing `proctor` job.

Why: a standard that nobody can see being skipped is not a standard.

Sources: [OWASP CICD-SEC-1 Insufficient Flow Control Mechanisms](https://owasp.org/www-project-top-10-ci-cd-security-risks/);
[OpenSSF Scorecard: SAST](https://github.com/ossf/scorecard/blob/main/docs/checks.md) (a check for whether analysis
runs at all).

**How the stack holds it: Checked.** PROCTOR's `ci-pipelines` check reads `.gitlab-ci.yml` and
`.github/workflows/ci.yml`: it fails a stack package whose pipeline is missing or runs no `composer ci`, and warns when
the pipeline switches Composer's audit off or runs `composer update`. PROCTOR's `preflight-pinned` check warns on an
include not pinned to a version or SHA, and its `preflight-gates` check (2026-11-09) warns on no Preflight include
(`proctor/preflight-gates/no-include`), `allow_failure` on a gate (`proctor/preflight-gates/allow-failure`) and no
proctor job (`proctor/preflight-gates/no-proctor-job`). Both warn and never fail. `tests/check-preflight-gates-warns.sh`
(and its `.ps1` twin) proves the no-include, no-proctor-job, allow-failure and unpinned warnings with the real PROCTOR,
and that none of them fails the run. Rollcall's "apps with CI" number is a plan.

### 3.4 Control when pipelines run, once, in the app
Set `workflow:rules` so a branch with an open merge request does not run twice, and so merge request pipelines exist.

Why: components set no `rules`, and two pipelines per push waste runner time.

Sources: [GitLab: merge request pipelines](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/);
[GitLab: CI/CD YAML, `workflow:rules`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Documented.** The README's "When the components run" section has a `workflow:rules` example
and says it must be copied into each app's own `.gitlab-ci.yml`. The components still leave `rules` unset.

Second pass: GitLab's merge request pipeline page says the `merge_request_event` rule must be in the app's own
`.gitlab-ci.yml`. Rules that arrive through `include:component` do not satisfy it. So the README cannot fix this from the
component side, and the example has to be copied into each app.

### 3.5 Restrict who can set pipeline variables, and prefer inputs
Set "Minimum role to use pipeline variables" to `no_one_allowed` for projects that do not need it. Pass parameters as
inputs.

Why: input values are fixed for the whole run and are type checked, while variables can change during the run. GitLab
recommends inputs over pipeline variables and, for stronger security, disabling pipeline variables once inputs are used.
On GitLab.com new projects default to `no_one_allowed`. On self-managed GitLab the default is `maintainer`.

Sources: [GitLab: CI/CD variables, pipeline variable restrictions](https://docs.gitlab.com/ci/variables/);
[GitLab: CI/CD inputs](https://docs.gitlab.com/ci/inputs/).

**How the stack holds it: Documented.** The components use inputs, which is right, and the README's "What the
components cannot force" section tells app owners to set "Minimum role to use pipeline variables" to `no_one_allowed`
unless the project needs pipeline variables.

### 3.6 Keep untrusted code away from secrets and from the install step
Do not run fork merge request pipelines with protected variables. Review a fork's `.gitlab-ci.yml` before running it.

Why: GitLab says a fork's merge request pipeline runs the fork's configuration, and that malicious code "can compromise
both masked and protected variables". Protected variables and runners reach a merge request pipeline only if both
branches are protected, the user has push or merge access to the target and both branches are in the same project. Fork
pipelines never get that access. This also matters for Composer: the April 2026 Composer flaws (see 4.4) are triggered
by a hostile `composer.json`, which is exactly what a contributed branch can carry.

Sources: [GitLab: merge request pipelines](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/);
[GitLab: CI/CD variables](https://docs.gitlab.com/ci/variables/).

**How the stack holds it: Documented.** All fourteen templates use no secrets, which limits the harm, and the README
documents the rule: review a fork's `.gitlab-ci.yml` before running its pipeline, and never give it protected variables.

---

## 4. The supply chain inside the jobs

### 4.1 Pin container images by digest, and update the pin through review
`php:8.4-cli` and `composer:2` are tags, and a publisher can repoint a tag.

Why: a pinned digest gives the same image every run. Without an update process, a pin also freezes security fixes.

Sources: [GitLab: pipeline security, Docker images](https://docs.gitlab.com/ci/pipeline_security/);
[Docker: build best practices, pin base image versions](https://docs.docker.com/build/building/best-practices/);
[OpenSSF Scorecard: Pinned-Dependencies](https://github.com/ossf/scorecard/blob/main/docs/checks.md).

**How the stack holds it: Enforced.** The `proctor` and `composer-audit` image defaults carry a digest
(`php:8.4-cli-trixie@sha256:...` and `composer:2.11.1@sha256:...`), and the README's "Updating image pins" says how to move them.
The exception is `php-test`: its matrix image `php:${PHP_VERSION}-cli-trixie` is still a tag, because each version would need its own digest.
The template lint (`bin/lint-templates`, run by `composer ci`) fails on `latest` or tag-less images and warns on tag-only images, so a new template cannot drift back to an unpinned image without a reviewed `lint-allow.yml` entry.

Second pass: GitLab's pipeline security page says "Always use SHA digests for Docker images". Renovate documents the
usual way to live with that: keep the tag and add the digest (`image:tag@sha256:...`), and let a bot open a change when the
digest moves. Be careful with automerge settings that skip review (see 1.7). A digest on a matrix image
(`php:${PHP_VERSION}-cli-trixie`) needs one digest per version, so the matrix would need to carry the digest too.

### 4.2 Use images the instance controls, and test on the image family of the target you deploy to
Pull through a registry or proxy under WSU's control, and test on the image family of the target you deploy to.
Citadel's images are the `citadel` target, and the official `php` images are the default for raw Docker, OpenShift
and Coolify.

Why: Docker Hub rate limits and tag changes can fail a pipeline, and a Debian `php:*-cli` image can differ from the
deploy image in extensions and settings.

Sources: [GitLab: dependency proxy for container images (all tiers)](https://docs.gitlab.com/user/packages/dependency_proxy/);
[Docker: build best practices](https://docs.docker.com/build/building/best-practices/).

**How the stack holds it: Documented.** The templates use the official `php` images from Docker Hub, the default for
raw Docker, OpenShift and Coolify. For the `citadel` target, the jobs should run on Citadel's own images; the
templates do not switch on the target yet.

Second pass, rate limits re-checked in Docker's docs: unauthenticated pulls are limited to 100 per 6 hours per IPv4
address or IPv6 /64 subnet, and free authenticated users to 200 per 6 hours. A shared instance runner usually sits behind
one address. A default pipeline pulls about five images (three PHP versions, `composer:2`, `php:8.4-cli`), so
twenty cold pipelines per six hours would use up the unauthenticated limit for the whole runner. That is arithmetic
from the documented limit and an assumed single address, not a measured result. GitLab's dependency proxy for container
images is on all tiers, is enabled by default on self-managed, caches manifests and layers, and supports pulls by digest
through `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/image@sha256:...`. It can also hold Docker Hub credentials for the group.

### 4.3 Verify every tool you download
Check the signature or checksum before you run it.

Why: an unverified download runs with the job's access.

Sources: [GitLab: pipeline security, shell tools](https://docs.gitlab.com/ci/pipeline_security/);
[Composer: download and installer verification](https://getcomposer.org/download/).

**How the stack holds it: Enforced.** The `php-test` and `proctor` templates fetch the Composer installer, compare its
SHA-384 with the published signature, and exit 1 on a mismatch, which fails the job.

### 4.4 Install from the lock and run only the code you need
Use `composer install`, not `update`. Where a job only inspects code, turn off plugins and scripts.

Why: install runs the app's scripts and plugins with the job's access.

Sources: [Composer CLI: `install`, `--no-plugins`, `--no-scripts`](https://getcomposer.org/doc/03-cli.md);
[OWASP CICD-SEC-4](https://owasp.org/www-project-top-10-ci-cd-security-risks/).

**How the stack holds it: Documented.** The templates use `composer install`, which is right, and the `proctor`
job now installs with `--no-plugins --no-scripts`, because the job only inspects the app; a contract test
(`tests/check-proctor-install-flags.sh` and its `.ps1` twin) pins those flags. What remains is running PROCTOR
without installing the app at all (gap item 5 option B), which is behind the PROCTOR PHAR work. An app on an
old PHP floor cannot be installed on `php:8.4-cli`, so the check may never run for it.

Second pass, why this matters more now: in April 2026 two Composer flaws (CVE-2026-40176, CVSS 7.8, and CVE-2026-40261,
CVSS 8.8) allowed arbitrary command execution as the user running Composer. One is triggered by a `composer.json` that
declares a Perforce repository, and the maintainers say Composer runs the injected commands even when Perforce is not
installed. The other is a shell escaping flaw reachable through a crafted source reference, including from package
metadata served by a malicious repository. Fixed versions are 2.9.6 and 2.2.27. Further security fixes followed in 2.10.1
(2026-06-04), 2.10.2 (2026-07-01) and 2.10.3 (2026-08-27), including a Perforce URL injection (CVE-2026-84361) and a
bin path symlink traversal (CVE-2026-59944). The mitigation advice in the news report is to run Composer only on projects
from trusted sources.
Composer 2.11.0 (2026-10-29) fixed two more: package names in `installed.json` that could escape the vendor directory
(GHSA-c968-33g3-wh7p) and inline repository HTTP headers, such as API tokens, written into `composer.lock`
(GHSA-fm2w-xgf2-f9fh). 2.11.1 (2026-10-30) fixed regressions only. Composer's maintenance table no longer lists 2.10.x,
so the stack pins 2.11.1.
Composer 2.10.0 also began enforcing `allow-plugins` for old lock files. The 2.10.3 and 2.11.0-RC1 details come from the
Composer GitHub releases page, which was read in this pass. The CVE records on NVD were not read.

Sources: [The Hacker News: Composer flaws](https://thehackernews.com/2026/04/new-php-composer-flaws-enable-arbitrary.html);
[Composer releases](https://github.com/composer/composer/releases).

### 4.5 Commit the lock file, and let a check say so
Composer's docs say to commit `composer.lock`. `composer install` with no lock resolves new versions and succeeds.

Why: the template alone would not notice a missing lock.

Sources: [Composer basic usage: the lock file](https://getcomposer.org/doc/01-basic-usage.md).

**How the stack holds it: Checked.** PROCTOR's `lock-committed` fails when the lock is missing. It runs only if the app
includes the `proctor` component, whose default command now runs on a fresh app (see 6.1).
`tests/check-proctor-lock-fails.sh` (and its `.ps1` twin) proves the check itself with the real PROCTOR on a copy of
the fixture app whose lock is removed after the install. Gap: the `proctor` component runs `composer install` first, and
Composer writes a new lock when none is committed, so inside the component an app that never committed its lock still
passes `lock-committed`. Closing it needs `lock-committed` to ask whether git tracks `composer.lock`, not whether the
file is on disk.

### 4.6 Audit the lock and fail the job
Run `composer audit --locked`. A non-zero exit fails the job. Give the audit no `allow_failure`.

Why: a known vulnerability should stop the merge.

Sources: [Composer CLI: audit](https://getcomposer.org/doc/03-cli.md);
[Composer 2.10 release](https://blog.packagist.com/composer-2-10-release/).

**How the stack holds it: Checked.** The `composer-audit` job fails on Composer's exit code. Composer also fails on
malware and, by its configured default, on abandoned packages, and PROCTOR's own audit check reads only advisories.
The two can disagree. The job's image is digest-pinned (`composer:2.11.1@sha256:...`, see the README's "Updating image
pins"), so the rules depend on the pinned digest, not on where the `composer:2` tag points. Tested on that digest
(Composer 2.11.1, and before it 2.10.3): `tests/check-composer-audit-fails` (run in CI by `must-fail-composer-audit`) runs the template's
own lines and proves an advisory and a malware-flagged version exit 1 in every `abandoned` mode, an abandoned package
exits 1 only in `fail` mode, and the clean fixture app exits 0.

The front-end half is the `npm-audit` job: `npm audit --omit=dev --audit-level=high` (both inputs) on the app's
`package-lock.json`, failing on npm's exit code with no `allow_failure`, then a full report with dev dependencies that
never fails. It passes `--audit=true --offline=false`, because an `.npmrc` with `audit=false` or `offline=true` makes npm
skip the request and print "found 0 vulnerabilities" (tested on npm 10.9.2). An unreachable registry fails the job; an
app with no lock file passes with a "nothing to audit" line. `audit_level` takes CREED's `medium` and runs it as npm's
`moderate`. `tests/check-npm-audit-fails` (run in CI by `must-fail-npm-audit`) runs the template's own script and proves
a high advisory (lodash 4.17.20, GHSA-35jh-r3h4-6jhm) fails at `high` and `medium` and passes at `critical`, the
`.npmrc` trap still fails, a dev-only finding fails only with `omit_dev: false`, and an unreachable registry fails a
clean lock.

Second pass, corrections and detail from Composer's current docs:

- Composer 2.10.0 (2026-05-28) changed the `audit` exit code to 0 on success and 1 if anything fails. Earlier releases
  used a different scheme. The CI job only needs "non-zero fails", so nothing breaks, but any script that read the old
  codes must change.
- Composer 2.10 added a `policy` config block for advisories, abandoned packages and malware. It replaces most of the
  `audit` block. `audit` still works as a fallback in 2.10 and is due to warn as deprecated in 2.11. An app that sets
  `config.audit.ignore` today should plan to move it.
- Malware: Composer 2.10 removes flagged versions from resolution and also checks at `composer install`, so a flagged
  version already in a lock file fails the install. Packagist takes the data from Aikido (since March 2026).
- Resolved by test: Composer's config page lists `policy.abandoned.audit` with default `fail` (and the older
  `audit.abandoned` defaulting to `fail` since Composer 2.7), while the Packagist 2.10 post says audit "only reports"
  abandoned packages. The config page is right: on Composer 2.10.3 and 2.11.1, `composer audit --locked` exits 1 on
  `tests/audit-fixtures/abandoned` with no flag or `--abandoned=fail`, and 0 with `report` or `ignore` (see 7.2).
- Malware, by test: `composer audit --locked` also reads Packagist's `malware` filter list (Composer's
  `policy.malware.audit`, default `fail`), and the `--abandoned` flag does not relax it: the malware fixture exits 1 in
  every mode, with the package, the list, the source (`aikido`) and a `PKFE-` ID in the table.
- `composer audit` has an `--ignore-unreachable` flag. Do not set it by default, because it hides the case where the
  advisory source cannot be reached. This is a recommendation, not a documented default.
- `--abandoned=ignore|report|fail` and `COMPOSER_AUDIT_ABANDONED` let an app set its own rule. Decide the stack's rule
  and write it down.

Sources: [Composer config: audit and policy](https://getcomposer.org/doc/06-config.md);
[Composer CLI: audit](https://getcomposer.org/doc/03-cli.md);
[Composer releases](https://github.com/composer/composer/releases).

### 4.7 Re-run the audit on a schedule
Add a scheduled pipeline so new advisories show up between commits.

Why: advisories are published after code is merged.

Sources: [OpenSSF Scorecard: Vulnerabilities](https://github.com/ossf/scorecard/blob/main/docs/checks.md).

**How the stack holds it: Documented.** The README's "Run it on a schedule" note under `composer-audit` says to create a weekly pipeline schedule on the default branch (project settings, Build, Pipeline schedules), and the component carries no `rules:` block, so it runs in scheduled pipelines. The schedule itself is a project setting that Preflight cannot create or check.

### 4.8 Cache dependencies under a fixed key and keep protected and unprotected caches apart
Cache Composer and npm downloads under a fixed key per job, not a lock-file hash. Leave GitLab's separation of protected and unprotected caches on.

Why: pipelines run faster, and an unreviewed branch cannot poison the cache that a protected branch uses.

Sources: [GitLab: caching](https://docs.gitlab.com/ci/caching/).

**How the stack holds it: Checked.** `php-test`, `proctor`, `pint`, `phpstan`, `sbom` and `squire-kit` cache Composer downloads in `.composer-cache/`, and `eslint` and `a11y` cache npm downloads in `.npm-cache/`, each under a fixed key: `preflight-php-${PHP_VERSION}` for `php-test`, one key per PHP version, and `preflight-proctor`, `preflight-pint`, `preflight-phpstan`, `preflight-sbom`, `preflight-squire-kit`, `preflight-eslint` and `preflight-a11y` for the rest. `tests/check-php-test-cache` (and its `.ps1` twin) fail if the key turns back into a lock-file hash or drops the PHP version, and `tests/check-proctor-cache` (and its `.ps1` twin) fail if the proctor key turns back into a lock-file hash. `composer-audit` still defines no cache. `npm-audit` installs nothing; it reads the app's own npm cache under the fixed key `npm` and path `.cache/npm/` (the ones Sourdough's generated pipelines use) with `policy: pull`, so it never overwrites what the install job downloaded. Every component cache also saves with `when: always`, so a retry after a dropped download fetches only what is missing, and `tests/check-dependency-cache` fails on a block without it. `tests/check-cache-fails.sh` (and its `.ps1` twin) proves all three guards fail on five broken copies (lock-hash keys, a key without the PHP version, a renamed proctor key, a block without `when: always`).

Second pass: GitLab appends `-protected` or `-non_protected` to every cache key. Pipelines on protected branches or tags,
and pipelines started by a Maintainer or Owner, get `-protected`. The separation is on by default and GitLab calls it
"a security feature", to be switched off only when every Developer is highly trusted. GitLab suggests cache:key:files on
composer.lock; the stack does not follow it, because this runner has no shared cache and a lock-hash key
refetches every package on each lock bump. GitLab's page also warns that after a cache clear, unpinned dependencies can
pull a newer unreviewed
release. GitLab's page has no PHP or Composer example, so the Composer cache directory setup is not covered by a source.

### 4.9 Name the version of every tool you download
Install a named Composer release, not whatever is newest.

Why: pinned tools make a run repeatable, and Composer's audit behavior has changed between releases.

Sources: [GitLab: pipeline security, shell tools](https://docs.gitlab.com/ci/pipeline_security/);
[Composer: download, versioned releases with checksums](https://getcomposer.org/download/).

**How the stack holds it: Enforced.** `proctor` and `php-test` install the Composer release named by the
`composer_version` input (default `2.11.1`), after checking the installer's SHA-384. The input's regex,
`^2\.(9\.([6-9]|[1-9][0-9]+)|[1-9][0-9]+\.[0-9]+)$`, accepts 2.9.6 and later only (2.9.6 to 2.9.9, then 2.10 and up), so
a pin older than the stack's floor is refused at pipeline creation. `composer-audit` uses a digest-pinned
`composer:2.11.1` image, and `tests/check-composer-floor.sh` (and its `.ps1` twin) keeps the floor in both templates.

Second pass: this practice pulls two ways, and the guide should say so. A pinned Composer is repeatable, but Composer
shipped security releases on 2026-04 (2.9.6), 2026-06-04 (2.10.1), 2026-07-01 (2.10.2), 2026-08-27 (2.10.3) and
2026-10-29 (2.11.0), and 2.10.x is no longer maintained. Composer 2.2 is a long-term release that gets critical security fixes only, with a
stated minimum maintenance date of 2026-12-31. So pin a version, and move the pin through a reviewed change (see 1.7). Do
not pin and forget. Composer's download page publishes a SHA-256 file and a PGP signature for each versioned `composer.phar`.
The page's own installer example now shows a fixed SHA-384 value and points to `composer.github.io/pubkeys.html` for
cross-checking, while Preflight fetches `installer.sig` at runtime. The runtime fetch is acceptable (it comes from a
different host than the installer), but it is not what the page shows today. A versioned phar plus its published checksum
is the stricter choice.

Sources: [Composer: download page](https://getcomposer.org/download/);
[Composer releases](https://github.com/composer/composer/releases).

### 4.10 Name the Debian release in the image tag
`php:8.4-cli` follows whichever Debian release the image maintainers choose. As of 2026-10-27 the bare `cli` tags for
8.2 to 8.5 are Debian trixie, and bookworm builds carry an explicit `-bookworm` suffix.

Why: the templates run `apt-get install unzip git` on the image. A change of base release can change package names,
versions and the installed C libraries, and it can differ from what the target runs. Name the variant, or match the
image family of the target you deploy to.

Sources: [Docker Official Image: php](https://github.com/docker-library/docs/blob/master/php/README.md).

**How the stack holds it: Checked.** The `php:` defaults name the Debian release: `php-test` defaults to
`php:${PHP_VERSION}-cli-trixie` and `proctor` to `php:8.4-cli-trixie@sha256:...` (Debian 13, the release the
bare `cli` tags point at as of 2026-10-28). `tests/check-image-inputs.sh` (and its `.ps1` twin) fail if a
default `php:` tag loses its Debian release name. `tests/check-image-inputs-fails.sh` proves the release-name
half on a php-test default stripped of `-trixie`. For the `citadel` target, the jobs should run on Citadel's
own images; which Debian release those use is not stated in the documents read for this guide.

### 4.11 Use Composer's malware and advisory blocking, and review lock changes
Run Composer 2.10 or later so flagged versions are refused at install and audit. Review `composer.lock` diffs after any
`update` or `require`.

Why: 2026 had real Composer supply chain incidents. The Packagist team names the `intercom/intercom-php` compromise
(2026-04-30) and the `laravel-lang` credential stealer (2026-05-22), and describes taken-over GitHub accounts and stolen
tokens used to move or add tags. Packagist now imports Aikido malware results (since March 2026) and is making stable
versions immutable. The same post says `composer install` from an existing lock reproduces the locked commit hashes,
while `update` and `require` can rewrite lock entries. It also says a minimum release age (cooldown) policy is designed
but not available yet; Composer 2.11.0 shipped it as `policy.cooldown`. 2.11 is now Preflight's default image, and the
setting stays off: no component sets it, and whether apps should is CREED's call. Composer 2.10 deprecates falling back
from a failed dist download to a source download, because that could install a version a repository had blocked, and
2.11.0 removed the `source-fallback` option. No Preflight component sets it. The runner images need `git` today (see
the apt line in the templates), so check whether any app depends on the fallback.

Sources: [Packagist: supply chain security update](https://blog.packagist.com/an-update-on-composer-packagist-supply-chain-security);
[Packagist: Composer 2.10 release](https://blog.packagist.com/composer-2-10-release/).

**How the stack holds it: Checked.** `php-test` and `proctor` install the Composer release named by the `composer_version`
input (default `2.11.1`), and `composer-audit` runs on a digest-pinned `composer:2.11.1` image, so the 2.11 behavior is chosen,
not picked up by accident. The `contract` job keeps the defaults matched to `contract/inputs.json`, and
`must-fail-composer-audit` proves the audit still fails a lock holding a malware-flagged version
(`tests/audit-fixtures/malware`); reviewing lock changes after an `update` or `require` stays a human step.

### 4.12 When a JavaScript component arrives, install from the lock with scripts off
For the Vue paths, a future Preflight job should use `npm ci`, turn off install scripts by default and allow them only
for named packages, and keep tokens out of the job.

Why: the Shai-Hulud npm worm (second wave, November 2025) moved its payload to `preinstall`, stole CI and cloud
credentials and spread through the victims' accounts. Vendors recommend disabling install scripts in CI. One vendor guide
warns that this alone does not stop every variant, so pair it with short-lived tokens and limited outbound network access
(see 5.4).

Sources: [Semgrep: Shai-Hulud second wave](https://semgrep.dev/blog/2025/digging-for-secrets-sha1-hulud-the-second-coming-of-the-npm-worm);
[Better Stack: Shai-Hulud](https://betterstack.com/community/guides/scaling-nodejs/shai-hulud-attack/). These were read as
search summaries only, so details are unverified.

**How the stack holds it: Documented.** README.md "Shared conventions" records the rule. The `eslint` component runs `npm ci --ignore-scripts`. The `npm-audit` component reads only the lock and runs no package code at all.

### 4.13 Generate a CycloneDX SBOM and validate it
Produce a software bill of materials for every release, and fail the build on an invalid one.

Why: an SBOM is the manifest of what your app ships. Without it, a dependency audit is a guess, and a supply chain
incident is a surprise.

Sources: [CycloneDX: Composer generator](https://github.com/CycloneDX/cyclonedx-php-composer);
[OWASP: Software Bill of Materials](https://owasp.org/www-project-software-bill-of-materials/).

**How the stack holds it: Enforced.** The `sbom` component runs `composer CycloneDX:make-sbom --validate`, which fails
the job on an invalid SBOM, and publishes the file as an artifact. Like every component, an app can skip the include,
so the enforcement is "when included". The SBOM is the passenger manifest; without it, a stowaway is a mystery.

### 4.14 Check code style with the app's own Pint
Run the app's own Laravel Pint in test mode and fail the pipeline on style errors.

Why: a shared style gate keeps every app's PHP readable and consistent, and running the app's own config means the
standard is the one the app already agreed to, not one imposed by the template.

Sources: [Laravel Pint](https://laravel.com/docs/12.x/pint).

**How the stack holds it: Enforced.** The `pint` component installs the app's dependencies and runs
`vendor/bin/pint --test` against the app's own `pint.json`. Like every component, an app can skip the include, so the
enforcement is "when included".

### 4.15 Catch static analysis errors with the app's own PHPStan
Run the app's own PHPStan and fail the pipeline on static analysis errors, publishing a Code Quality report.

Why: static analysis finds bugs before they run, and a Code Quality report gives reviewers a per-file, per-line view
of what to fix. Running the app's own config means the level and paths are the ones the app already agreed to.

Sources: [PHPStan](https://phpstan.org/); [GitLab: Code Quality](https://docs.gitlab.com/ci/testing/code_quality/).

**How the stack holds it: Enforced.** The `phpstan` component installs the app's dependencies and runs
`vendor/bin/phpstan analyse --error-format=gitlab` against the app's own `phpstan.neon`, publishing the report. Like
every component, an app can skip the include, so the enforcement is "when included".

### 4.16 Lint JavaScript with the app's own ESLint and Prettier
Run the app's own ESLint (and Prettier) and fail the pipeline on lint or format errors.

Why: a shared lint gate keeps every app's JavaScript readable and consistent, and running the app's own config means
the standard is the one the app already agreed to, not one imposed by the template.

Sources: [ESLint](https://eslint.org/); [Prettier](https://prettier.io/).

**How the stack holds it: Enforced.** The `eslint` component installs the app's dependencies with
`npm ci --ignore-scripts` and runs `npx --no-install eslint` and `npx --no-install prettier --check` against the
app's own config. Like every component, an app can skip the include, so the enforcement is "when included". ESLint is
the preflight checklist for your JavaScript.

### 4.17 Build images without privileged runners or the Docker socket
Do not give a job `privileged: true`, a Docker-in-Docker service, or a mount of the host's `/var/run/docker.sock`
just to build an image.

Why: a privileged container can reach the host's devices and step outside the sandbox, and a mounted Docker socket
hands the job the host's Docker daemon, which runs as root on the machine. Either one turns a CI job into a path to
the runner host, and on a shared instance runner that is every project on it.

Sources: [GitLab Runner: security](https://docs.gitlab.com/runner/security/);
[CISA and NSA: Defending CI/CD environments](https://cisa.gov/news-events/alerts/2023/06/28/cisa-and-nsa-release-joint-guidance-defending-continuous-integrationcontinuous-delivery-cicd).

**How the stack holds it: Enforced.** The template lint (`bin/lint-templates`, run by `composer ci`) fails a
template on all four patterns. Rule `privileged` reports "privileged: true is not allowed"; rule `dind-service`
reports "Docker-in-Docker service is not allowed" for any `docker:dind` or `*-dind` service; rule `docker-sock`
reports "references docker.sock" for any string that names the socket; rule `kaniko-image` reports "Kaniko image is
not allowed" for a Kaniko image or service. None of the components builds an image, so nothing in `templates/` needs
an allowlist entry.

What to do instead: keep image building out of the pipeline jobs. Where a build must run in CI, use a builder that
does not need privileges, such as [BuildKit in rootless mode](https://github.com/moby/buildkit/blob/master/docs/rootless.md)
or [Buildah](https://buildah.io/) run rootless. Kaniko is not the fallback here: Google archived the upstream project
in 2025, so it no longer gets fixes, and the lint rejects it. The runner side of the same rule is 5.3. A mounted
Docker socket is the one line the preflight checklist never signs.

---

## 5. Secrets, tokens and runners

### 5.1 Keep secrets out of components and CI files
Components hold no credentials. Where a job needs one, it comes from a masked, hidden and protected variable or an
external secret store, and the component takes it as an input name, not a value.

Why: CI file contents are readable by everyone with repo access, and masking is not a guarantee.

Sources: [GitLab: CI/CD variables](https://docs.gitlab.com/ci/variables/);
[GitLab: pipeline security, secrets](https://docs.gitlab.com/ci/pipeline_security/);
[OWASP CICD-SEC-6 Insufficient Credential Hygiene](https://owasp.org/www-project-top-10-ci-cd-security-risks/).

**How the stack holds it: Documented.** The fourteen templates use no secrets, which is good. Nothing fails if a later
template adds one. The repository's own pipeline runs GitLab's pipeline secret detection, and since 2026-11-10 the
`secret_detection` job blocks: it was advisory for a week of green runs from 2026-11-02. GitLab's template marks the
job `allow_failure: true` itself, so `.gitlab-ci.yml` sets `allow_failure: false` on it, and
`tests/check-secret-detection.sh` and its `.ps1` twin fail the `contract` job if that override goes missing or turns
advisory again. It
runs on the git.wayne.edu instance (Community Edition): every `secret_detection` job there passed from 2026-11-09 to
2026-11-10.

Second pass: GitLab's pipeline secret detection is available on Free, Premium and Ultimate. Its docs show
`include: template: Jobs/Secret-Detection.gitlab-ci.yml`, and the error messages reference gitleaks. Limits: it needs a
Linux runner with the Docker or Kubernetes executor, an amd64 CPU, and a `test` stage in the pipeline. On Free and
Premium the findings are in the job's JSON output only, not in merge request reports. The page does not mention
Community Edition, so whether it works on git.wayne.edu is unverified. GitLab's default variable visibility has been
Masked since 18.3, and a variable can be created as masked and hidden only at creation time. GitLab's components page
also advises minimally scoped, short-lived tokens.

Sources: [GitLab: pipeline secret detection](https://docs.gitlab.com/user/application_security/secret_detection/pipeline/).

### 5.2 Limit what the job token can reach
Keep the project's CI/CD job token allowlist short. Add a project only for real cross-project access. Use fine-grained
permissions where they fit.

Why: a leaked job token acts with the triggering user's access.

Sources: [GitLab: CI/CD job token](https://docs.gitlab.com/ci/jobs/ci_job_token/).

**How the stack holds it: Documented.** It matters when private packages (served from GitLab's own package registry) need a
token. The README's "Keep the job token allowlist short" section now sets the rule, and says plainly that the
allowlist is a project setting Preflight cannot create or check.

Second pass: the GitLab docs say the allowlist is on by default and a project's list starts with only itself. The option to
allow all groups and projects shows only on self-managed or Dedicated instances, and only when enforcement is off. GitLab
calls disabling the allowlist "a security risk". Prefer adding single projects over groups, because a group entry covers
every project under it at any depth, including ones created later. Keep "Allow Git push requests" off unless needed.
Use the `JOB-TOKEN` header, not a query string. Review the job token authentication log. The page links to fine-grained
permissions for REST endpoints but does not state whether that feature is beta or GA, so treat it as unverified.

### 5.3 Use ephemeral, isolated, non-privileged runners
Prefer a Docker executor without privileged mode, one job per fresh environment, and no shell executor shared by
projects.

Why: any Developer can run code on a shared runner, and a non-ephemeral one can leak between projects.

Sources: [GitLab Runner: security](https://docs.gitlab.com/runner/security/);
[CISA and NSA: Defending CI/CD environments](https://cisa.gov/news-events/alerts/2023/06/28/cisa-and-nsa-release-joint-guidance-defending-continuous-integrationcontinuous-delivery-cicd).

**How the stack holds it: Documented.** The stack's instance-runner case expects a Docker executor and leaves capacity,
maintenance and limits to ops. The README's "Strongly recommended: a git.wayne.edu instance runner" section now
states the request wording: a non-privileged Docker executor (no privileged mode, no Docker socket mount), a
fresh ephemeral environment for every job, and no shell executor shared between projects.

Second pass, concrete settings from the GitLab Runner security page, to put in the runner request:

- Do not run privileged mode or `--pid=host`. GitLab says Docker "can be considered safe when running in non-privileged
  mode".
- Use `pull_policy = always` on runners shared by projects with mixed access, and never `if-not-present`. The page shows
  a user who lacks registry credentials still using a cached private image. Note that `always` increases manifest pulls,
  which feeds the Docker Hub limit in 4.2, so pair it with a dependency proxy.
- Do not use the shell executor for builds that share a machine. GitLab says to use it "only for running trusted builds".
- With `GIT_STRATEGY: fetch` on a reusable build directory, anyone with access to that copy can add code that runs in
  other users' pipelines. Enabling `FF_ENABLE_JOB_CLEANUP` on static hosts cleans the directory after each build.
- A cloned runner can take jobs meant for the original, so do not clone runner registrations.

### 5.4 Decide which hosts a job may reach
List what jobs need: the package registry, npm, Docker Hub or a proxy, the Composer installer host, the Debian mirror
that `apt-get` uses, and the advisory source.

Why: network limits reduce what a bad job can send out.

Sources: [GitLab Runner: security, network segmentation](https://docs.gitlab.com/runner/security/).

**How the stack holds it: Documented.** The instance runner case lists network access as an open question for ops.

### 5.5 Keep the GitLab instance and runners patched, and know the version
Ask ops for the GitLab version and runner version, and for the patch schedule. Subscribe to GitLab's patch release notices.

Why: GitLab's critical patch of 2026-10-12 (fixed in 19.4.2, 19.3.5 and 19.2.8, for Community and Enterprise) fixed
CVE-2026-97229, CVSS 10.0, an integer overflow in the CI/CD regular expression compiler. GitLab's page says an
unauthenticated user could run arbitrary code on the server using a crafted regular expression in a CI/CD configuration.
The same release fixed CVE-2026-16301 (High, 8.5: a Developer could run pipelines on protected branches without
authorization) and CVE-2026-14814 (High, 8.2: cache poisoning of raw repository file responses that could expose protected
environment variables). GitLab's page does not tell self-managed owners to rotate runner tokens. Some secondary reports
do, and they disagree on dates, so check GitLab's own advisory and ops' judgment before acting on that advice. Every
Preflight job depends on this instance being sound, and the guide cannot tell whether git.wayne.edu is patched because its
help page shows no version.

Sources: [GitLab patch release 19.4.2, 19.3.5, 19.2.8](https://docs.gitlab.com/releases/patches/patch-release-gitlab-19-4-2-released/).

**How the stack holds it: Not yet.** Instance patching is outside the Preflight repo. Record the owner and the schedule in
the instance runner request.

---

## 6. Staying current with the policy

### 6.1 Make the `proctor` component runnable
The default command must work without extra options on a fresh app.

Why: a default that errors teaches developers to ignore the job.

Sources: [GitLab: component examples, defaults](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Checked.** The default `vendor/bin/proctor check --format=codequality` omits `--policy`,
which used to make it exit 2. Since PROCTOR 0.2.1 the policy resolves without the option: `PROCTOR_POLICY`, then the
app's installed CREED policy, then the copy bundled with PROCTOR. This repository's pipeline includes the `proctor`
component at `$CI_COMMIT_SHA` against `tests/fixture-app` (`.gitlab-ci.yml:11`), so the real PROCTOR runs the default
command on every pipeline, and the `contract` job runs `tests/check-proctor-fails` on the failing and `--record`
fixtures (see 7.2).

### 6.2 Derive the PHP matrix from the policy, and drop end-of-life versions
The tested versions should be those the policy lists as supported, intersected with what the app declares.

Why: a hard-coded list goes stale when a version reaches end of life.

Sources: [PHP supported versions](https://www.php.net/supported-versions.php);
[GitLab: CI/CD YAML, `parallel:matrix`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Documented.** The default list is `["8.3", "8.4", "8.5"]`, so 8.2 is already out, and the
floor in the README is `^8.3`. Both are still hard-coded values rather than derived from CREED's policy, and 8.6 has
not been added anywhere. PHP 8.2 reaches end of life on 2026-12-31, and PHP 8.3 is already past active support.

Second pass: php.net's supported versions page was re-read on 2026-10-27 and the first pass is correct.

| Branch | Released | Active support ended or ends | Security support ends |
|---|---|---|---|
| 8.2 | 2022-12-08 | 2024-12-31 | 2026-12-31 |
| 8.3 | 2023-11-23 | 2025-12-31 | 2027-12-31 |
| 8.4 | 2024-11-21 | 2026-12-31 | 2028-12-31 |
| 8.5 | 2025-11-20 | 2027-12-31 | 2029-12-31 |

Two consequences. First, 8.2 is still supported today, but only for security fixes, until 2026-12-31. The
default list had to drop it in a release that ships before 2027-01-01, so apps have time to see it; the default has
since dropped it. Second, 8.4 moves to
security-only on the same day, so the "newest actively supported" version changes to 8.5 in 2027. The Docker Official
Image README still lists 8.2 (8.2.35), 8.3 (8.3.36), 8.4 (8.4.27) and 8.5 (8.5.12), and also lists 8.6 release
candidates. The 8.6 release date was not verified in this pass. An image existing on Docker Hub is not evidence that a
version is supported, so the policy must be the source of the list.
Prior art: Drupal's templates choose the PHP version from named variables for the core minimum and maximum, so the list
lives in one place. An array input with `options` (GitLab 19.0 or later, see 2.2) would give the same effect.

### 6.3 Test on every version the app claims to support
The matrix creates one job per version, up to 200 combinations.

Why: a constraint of `^8.2` is a promise about 8.2, 8.3, 8.4 and 8.5.

Sources: [GitLab: CI/CD YAML, `parallel:matrix`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Checked.** `php-test` creates one job per entry through `parallel:matrix`. The first
pipeline ran it on 8.2, 8.3, 8.4 and 8.5. `tests/check-php-matrix.sh` (and its `.ps1` twin) fails if the
`parallel: matrix:` block or the array-typed `php_versions` input goes away, and `tests/check-php-matrix-fails.sh`
proves it on broken copies; GitLab itself expands the matrix, so only a pipeline shows the jobs.

The matrix limit of 200 permutations was re-checked in the GitLab YAML reference and is correct.

### 6.4 Add an advisory job for the next PHP release
Run the tests on the next PHP version (a release candidate once one exists) in a job that may fail, so the app learns about
breakage before the version becomes supported.

Why: the Docker Official Image README already lists PHP 8.6 release candidates on 2026-10-27, and the matrix has no early
warning. An advisory job must not become a gate: only a final, supported version belongs in the required matrix.

Sources: [Docker Official Image: php](https://github.com/docker-library/docs/blob/master/php/README.md);
[PHP supported versions](https://www.php.net/supported-versions.php). The tag names for release candidates were not checked.

**How the stack holds it: Documented.** `php-test` takes `php_advisory_version`, which adds a `<job_name>-advisory` job with `allow_failure: true` (`templates/php-test/template.yml`); nothing yet proves the job in a pipeline.

### 6.5 Aim the future accessibility component at WCAG 2.2 AA
When Preflight gets an accessibility suite, use WCAG 2.2 Level AA as the floor, and keep a manual review step.

Why: on 2026-04-20 the US Department of Justice published an interim final rule that moved the Title II web accessibility
compliance dates by one year, to 2027-04-26 for public entities with a population of 50,000 or more and 2028-04-26 for
smaller ones. It did not change the standard, WCAG 2.1 Level AA. A trade press report says covered content includes
public educational institutions' portals, forms, learning management content and websites. Which date applies to WSU
depends on how the university is classified, so ask counsel. One search summary said the extension is being challenged in
federal court. That is unverified. Automated checks find only some failures, so a green job does not prove conformance.

The stack's floor is WCAG 2.2 Level AA, the same floor WayneUI's accessibility gate uses. W3C states that content
that conforms to WCAG 2.2 also conforms to WCAG 2.1, so meeting the 2.2 floor also meets the rule's 2.1 Level AA.

Sources: [Campus Technology: DOJ extends Title II deadline](https://campustechnology.com/articles/2026/04/27/doj-extends-deadline-for-ada-title-ii-compliance.aspx).
The Federal Register text itself was not read in this pass.

**How the stack holds it: Enforced where included.** The `a11y` component runs axe-core in Playwright and fails on any
violation. Its default tags are WCAG 2.1 Level AA, the rule's own level, so an app that adds the bare include meets the
rule's floor; the stack's sites and Preflight's own pipeline pass `wcag22aa` for the 2.2 floor. Its JSON report counts
the results axe-core marks for a person to review, which keeps the manual step in view, and the docs page says a green
job is not proof of conformance.

---

## 7. Testing the components

### 7.1 Test each component from the commit under review
Include the component with `$CI_COMMIT_SHA` in the project's own pipeline, against a sample app.

Why: it exercises exactly what will be released.

Sources: [GitLab: components, testing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Checked.** `.gitlab-ci.yml` includes ten components at `$CI_COMMIT_SHA`: `proctor`, `php-test`,
`composer-audit`, `pint` and `phpstan` against `tests/fixture-app`, `sbom` in the project root, `npm-audit` against the
clean lock in `tests/npm-audit-fixtures/clean`, `a11y` against this repository's own `site` (the stack's floor, WCAG 2.2
AA), `squire-kit` against the kit Squire wrote in `tests/squire-kit-fixture`, and `portability` against the clean build in
`tests/portability/app`, plus a `contract` job running the `tests/check-*.sh` scripts.

### 7.2 Test the failing cases, and that the expected jobs exist
Each component needs a fixture that must fail it: a failing test, an advisory, a policy violation. A test can also
confirm that the expected job was created.

Why: a component that never fails looks the same as one that works.

Sources: [GitLab: components, testing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Partly.** Eleven components carry a must-fail fixture that a `must-fail-` job in `.gitlab-ci.yml`
runs, and `proctor`'s main fixture runs in the `contract` job (its lock fixture, `tests/check-proctor-lock-fails`, runs in
`must-fail-proctor-lock`): `proctor` runs the template's own `--record` guard and command line
on `tests/proctor-fails`, a fake proctor that prints one blocker finding and exits 1, against the clean stubs in
`tests/fixture-app` (no `--record`, like PROCTOR 0.10.0) and `tests/proctor-record` (with it), and proves `proctor.json`
is kept only when PROCTOR can write it (`tests/check-proctor-fails`, run in CI by the `contract` job); `composer-audit`
runs the template's own script lines on `tests/audit-fixtures/advisory` (laravel/framework v9.0.0, which must fail
naming CVE-2024-52301) and `tests/audit-fixtures/malware` (aikido/endpoint-test 0.0.1, Aikido's harmless package
flagged on Packagist's malware list on purpose, which must fail naming it), both in every `abandoned` mode, and on
`tests/audit-fixtures/abandoned`, which fails only in `fail` mode, against the clean case in `tests/fixture-app`
(`tests/check-composer-audit-fails`, run in CI by `must-fail-composer-audit`; it needs Packagist, and a run without it
fails rather than passes); `npm-audit` runs the template's own script on fixed locks in `tests/npm-audit-fails` and
`tests/npm-audit-fixtures`: lodash 4.17.20 (GHSA-35jh-r3h4-6jhm, high) fails at high and medium and passes at critical,
an `.npmrc` that turns the audit off still fails, a dev-only finding fails only with `omit_dev` false, and a clean
lock, an app with no lock and an unreachable registry behave as the docs say (`tests/check-npm-audit-fails`, run in CI
by `must-fail-npm-audit`); `a11y` checks the bad site in `tests/a11y-fixtures/bad`, which fails with each flaw named
(`tests/check-a11y`, run in CI by `must-fail-a11y`); `portability` builds `tests/portability/app` once clean and once per flaw
(needs root, writes outside its paths, fixed port, host-bound health, a baked `.env`, trusts any proxy, file logs, file
sessions, no SIGTERM handler) and passes only when the clean build passes and each flaw fails the check it targets
(`tests/check-portability`, run in CI by `must-fail-portability`); `php-test` runs PHPUnit on `tests/php-test-fails`,
which carries a failing test, against the clean case in `tests/fixture-app` (`tests/check-php-test-fails`, run in CI by
`must-fail-php-test`); `phpstan` runs PHPStan on `tests/phpstan-fails`, which carries a type error, against the clean
case in `tests/fixture-app` (`tests/check-phpstan-fails`), and `pint` runs Pint in test mode on `tests/pint-fails`,
which is not formatted to the standard, against the clean case in `tests/fixture-app` (`tests/check-pint-fails`), both
run in CI by `must-fail-phpstan-pint`; `eslint` runs the app's own ESLint and Prettier on `tests/eslint-fails`, which
carries one unused `const`, against the clean case in `tests/eslint-clean` (`tests/check-eslint-fails`, run in CI by
`must-fail-eslint`); `secret-detection` runs the template's own gitleaks command, with the template's own config, on
`tests/secret-detection-clean` plus a token built at run time in `src/config.php`, which must fail with `gitlab-pat`
named and the value redacted from the log, while the same token planted in `vendor/` and `node_modules/` must stay
invisible (`tests/check-secret-detection-fails`, run in CI by `must-fail-secret-detection`); `sbom` runs Composer and
the CycloneDX plugin on `tests/sbom-fails`, whose `composer.lock` is not valid JSON, against the clean case in
`tests/sbom-clean`, whose SBOM lists `psr/log` and not the dev-only `psr/container` (`tests/check-sbom-fails`, run in
CI by `must-fail-sbom`); `squire-kit` runs the template's own script against the clean kit in
`tests/squire-kit-fixture`, which must pass, a copy with a line appended to `.squire/php-web.ini`, which must fail
naming the file, and a copy with no `.squire.json`, which must stop with exit 2 (`tests/check-squire-kit-fails`, run
in CI by `must-fail-squire-kit`); and `package-publish`'s offline guards stop a non-semantic-version tag and a missing
`composer.json` before any registry contact (`tests/check-package-publish-fails.sh`, run in CI by
`must-fail-package-publish`). Still missing: `package-publish`'s moved-version path needs a live registry and stays untested; `renovate` is
a config, not a job, so it has nothing to fail.

### 7.3 Use the stack's own projects as the first users
Each stack repo includes Preflight, pinned.

Why: the people who write the components feel their faults first.

Sources: [GitLab: components, testing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** PROCTOR and CREED include `php-test` and `composer-audit` at a pinned SHA.
git.wayne.edu now has an instance runner, and the stack's CI runs on it. Every product in the stack still strongly recommends a git.wayne.edu instance runner, so that capacity stays there.

### 7.4 Let a developer run the same checks on Windows, macOS and Linux without bash
Give each check a command that runs the same way on every OS, such as a Composer script, and have the CI job call it. Keep
a container-based local run as an extra.

Why: the stack needs a native path on each OS and Windows must never require bash. Prior art: Drupal's template project
points people to Composer scripts that mimic its CI (through a DDEV service), and to `gitlab-ci-local` for running the CI
containers. Its page gives no Windows-specific guidance, needs Docker, and lists limits (for example, HTTPS clones do not
fully work). Whether `gitlab-ci-local` supports `component:` includes and `spec:inputs` was not confirmed. GitLab's own
local runner is described there as deprecated.

Sources: [Drupal gitlab_templates: test locally](https://project.pages.drupalcode.org/gitlab_templates/info/test-locally/);
[Drupal: GitLab CI strategy](https://www.drupal.org/drupalorg/blog/gitlab-ci-drupals-strategy-to-empower-a-whole-ecosystem).

**How the stack holds it: Documented.** The README has a "Local checks" section with two `docker run` commands for the
fixture app. They are written as `sh` with `$(pwd)`, and this pass did not test them in PowerShell. They cover only the
fixture, not an app's own checks.

---

## Gaps for the backlog

Practices tagged `Not yet` or `Documented`, each one line. Highest value first.

1. Done: 6.1: The `proctor` default command works without `--policy` since PROCTOR 0.2.1 (`PROCTOR_POLICY`, then the
   app's installed CREED policy, then the copy bundled with PROCTOR), and both PROCTOR's and CREED's pipelines include
   `preflight/proctor@0.5.0`. 6.1 is `Checked`: this repository's pipeline runs the component on `tests/fixture-app`,
   and the `contract` job runs `tests/check-proctor-fails`.
2. 7.2: Add a failing fixture for `package-publish`'s moved-version path (it needs a live registry). The other
   components have theirs, and Preflight's pipeline runs the real PROCTOR.
3. Done: 3.3: PROCTOR's `preflight-pinned` and `preflight-gates` checks flag apps that skip, unpin or weaken
   Preflight. A Rollcall fleet report of the same is still a plan.
4. Done: 4.1: Image digests stay pinned, and the pins that matter most move through review: the shared preset
   `renovate/default.json` turns off automerge (and platform automerge) for updates inside the templates, the
   contract and this repository's own pipeline, and for component include version bumps, labelling them
   `needs-review`; `tests/check-renovate-review.sh` (and its `.ps1` twin) keeps the rules in place.
5. Done (option A): 4.4: the `proctor` job installs with `--no-plugins --no-scripts`, pinned by a contract test. Option B remains: run PROCTOR without installing the app at all (behind the PROCTOR PHAR work).
6. Done: 1.3: The `release` job exists and runs on every tag after the test and audit stages, creating the GitLab Release through the Releases API; the `Catalog entry` still depends on the first tag run, because no release job has run for a tag yet. The components added after `0.1.0` already shipped in `0.1.1`.
7. Done: 1.2: Recorded the project's branch and tag protection as the README's "Protection checklist": protected
   default branch with a required merge request, protected release tags, merge request approvals of at least one,
   `no_one_allowed` pipeline variables, and no protected variables in fork pipelines. Checking them stays a human
   step: they are project settings Preflight cannot create or verify, and a read-only token drift report was
   considered and left out on purpose.
8. 6.2: Derive the PHP matrix from the policy, and drop 8.2 by 2027-01-01.
9. Done: 4.9: The Composer version the installer fetches and the `composer-audit` image are pinned: `proctor` and
   `php-test` install the named release (default `2.11.1`, floor 2.9.6, `templates/proctor/template.yml:26`),
   `composer-audit` runs the digest-pinned `composer:2.11.1` image (`templates/composer-audit/template.yml:16`), and
   `tests/check-composer-floor.sh` keeps the floor in both templates.
10. Done (partly): 2.2: the path-like inputs are constrained and pinned by `tests/check-path-input-regex`: `phpstan`
    `config` and `memory_limit`, `pint` `config` and `sbom` `output` carry input regexes (relative paths and PHP sizes).
    Left free by design: `test_command`, `proctor_command` and `eslint_args` (arbitrary commands and arguments).
11. Done: 4.7: Documented the scheduled audit in the README: a weekly pipeline schedule on the default branch (project settings, Build, Pipeline schedules); the component has no `rules:` and runs in scheduled pipelines, and the schedule itself is a project setting Preflight cannot create or check.
12. Done: 4.2: Every Docker Hub image goes through the Dependency Proxy: each component takes an `image_prefix` input
    (default `${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}`), kept in place by `tests/check-dependency-cache.sh`.
13. Done: 3.2: Branch and CI-file protection for app repos is recommended in the README's "Protection checklist"
    (README.md:755): a protected default branch with a required merge request, protected release tags, merge request
    approvals of at least one, `no_one_allowed` pipeline variables, and no protected variables in fork pipelines.
14. Done: 3.4: The `workflow:rules` example is in the README's "When the components run" (README.md:709).
15. Done: 2.5: Build job names from an input so one project can include a component twice.
16. Done: 4.8: every Composer and npm component caches under a fixed key, kept in place by `tests/check-php-test-cache` and `tests/check-proctor-cache`.
17. Done (advisory): 5.1: Added secret detection to Preflight's own pipeline as an advisory job (`allow_failure:
    true`); it turns blocking after a week of green pipelines.
18. Done: 5.2: Documented the job token allowlist rule in the README: list only the projects a private-package install
    really needs, use the fine-grained permissions where they fit, and review the list when a dependency is
    dropped; the allowlist is a project setting Preflight cannot create or check.
19. Done: 5.3: Stated the runner request wording in the README: a non-privileged Docker executor (no privileged mode,
    no Docker socket mount), a fresh ephemeral environment for every job, and no shell executor shared between
    projects.
20. 5.4: Agree the list of hosts jobs may reach.
21. Done: 1.4: The inputs contract is `contract/inputs.json`, held by `tests/ComponentsContractTest.php` (PHPUnit, in
    `composer ci`) and `tests/check-contract.sh` with its `.ps1` twin (the contract job); a renamed input or job, a
    changed type or a changed default fails the build, and `composer contract:update` rewrites the contract when the
    change was made on purpose.
22. 2.3 and 2.6: Lint templates for global keys, and explain which components may be weakened.
23. Done: 3.1: The "components do not force" limit is published in the README's "What the components cannot force"
    (README.md:735).
24. 5.3 and 5.4 and 7.3: git.wayne.edu now has an instance runner, and the stack's CI runs on it; every product in the stack still strongly recommends a git.wayne.edu instance runner, so that capacity stays there. What remains open: 5.4's list of hosts jobs may reach.

Added in the second pass (2026-10-27):

25. 5.5: Get the GitLab and runner versions and the patch schedule from ops, and record them in the instance runner
    request. A critical CI-related GitLab patch shipped on 2026-10-12.
26. 6.2 (updated): Derive the PHP matrix from the policy, and add 8.6 to the policy path when it is released. The
    default list has already dropped 8.2.
27. 4.9 and 4.6 (updated): Pin Composer to a named release with a reviewed bump path, and require 2.9.6 or later (2.11.1 is
    current), because of the April to August 2026 Composer security fixes.
28. Done: 4.6 and 7.2 (updated): fixtures for an advisory, an abandoned package and a malware-flagged version run in
    `must-fail-composer-audit` (`tests/check-composer-audit-fails`), and 4.6 records the real exit codes; the conflict
    on abandoned packages is settled (they fail by default).
29. Done: 1.7: The reviewed bump process is in place: Renovate runs from the private runner project, and the shared
    preset routes digest changes inside the templates, the contract and this repository's own pipeline, plus
    component include version bumps, to a `needs-review` label that never auto-merges. The `gitlabci` manager
    extracts an app's own `component:` includes, and the preset routes those repository dep bumps to review;
    `tests/check-renovate-review.sh` (and its `.ps1` twin) keeps that rule in place.
30. Done: 1.6: The tag-triggered `release` job puts the commit SHA in every GitLab Release note from the first tag run on, and the README and examples already tell apps to pin the SHA with the tag in a trailing comment.
31. 4.11: Write the stack's rule for Composer malware, advisory and abandoned policy, and require Composer 2.10 or later.
32. Done: 4.10: The image defaults name the Debian release: `php-test` `php:${PHP_VERSION}-cli-trixie`
    (`templates/php-test/template.yml:16`), `proctor` `php:8.4-cli-trixie` by digest (`templates/proctor/template.yml:16`),
    kept in place by `tests/check-image-inputs.sh`.
33. 2.9 (done): Add `timeout` and `interruptible` to each job.
34. Done: 3.4 (updated): The `workflow:rules` example lives in the README, and it says the rules must live in the app's
    own file (README.md:727).
35. Done: 3.5 and 3.6: The README's Protection checklist tells app owners to restrict who can use pipeline variables
    (`no_one_allowed`) and to keep fork merge requests away from protected variables (README.md:767).
36. Done: 2.10: `php-test` takes an `image` input (default `php:${PHP_VERSION}-cli-trixie`,
    `templates/php-test/template.yml:16`), like every other component.
37. 7.4: Add a cross-OS local run (Composer scripts first) and test the README's local commands in PowerShell.
38. Done: 6.4: `php-test` takes `php_advisory_version`, which adds a `<job_name>-advisory` job, advisory-only
    (`allow_failure: true`, `templates/php-test/template.yml:27,104`).
39. Done: 6.5: WCAG 2.2 AA is named as the floor on the front page (site/index.html:841), the same floor Preflight's
    own `a11y` job passes as `wcag_tags` (.gitlab-ci.yml:44).
40. 1.8: Write a retirement policy for components, and test whether SHA pins survive a Catalog unpublish.
41. Done: 4.12: The install-scripts rule is recorded in the README's "Shared conventions": JavaScript components
    install with `npm ci --ignore-scripts` (README.md:811).
42. Done: 2.11: Every template prints the `Preflight component <name> <version>` line first in every job
    (`templates/proctor/template.yml:75`), kept in place by `tests/check-component-version.sh` in the `contract` job
    (.gitlab-ci.yml:88).
43. Done (advisory): 5.1 (updated): added GitLab secret detection to Preflight's pipeline. Still open: confirm
    whether it runs on git.wayne.edu (Community Edition).

## Sources

All checked on 2026-10-27.

| Title | URL |
|---|---|
| GitLab: CI/CD components | https://docs.gitlab.com/ci/components/ |
| GitLab: CI/CD component examples | https://docs.gitlab.com/ci/components/examples/ |
| GitLab: CI/CD inputs | https://docs.gitlab.com/ci/inputs/ |
| GitLab: CI/CD YAML reference | https://docs.gitlab.com/ci/yaml/ |
| GitLab: use CI/CD configuration from other files | https://docs.gitlab.com/ci/yaml/includes/ |
| GitLab: pipeline security | https://docs.gitlab.com/ci/pipeline_security/ |
| GitLab: CI/CD variables | https://docs.gitlab.com/ci/variables/ |
| GitLab: CI/CD job token | https://docs.gitlab.com/ci/jobs/ci_job_token/ |
| GitLab Runner: security | https://docs.gitlab.com/runner/security/ |
| GitLab: caching in CI/CD | https://docs.gitlab.com/ci/caching/ |
| GitLab: merge request pipelines | https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/ |
| GitLab: protected branches | https://docs.gitlab.com/user/project/repository/branches/protected/ |
| GitLab: pipeline execution policies | https://docs.gitlab.com/user/application_security/policies/pipeline_execution_policies/ |
| GitLab: dependency proxy for container images | https://docs.gitlab.com/user/packages/dependency_proxy/ |
| GitLab: Code Quality | https://docs.gitlab.com/ci/testing/code_quality/ |
| Docker: build best practices | https://docs.docker.com/build/building/best-practices/ |
| Composer: download and installer verification | https://getcomposer.org/download/ |
| Composer: command-line interface | https://getcomposer.org/doc/03-cli.md |
| Composer: basic usage | https://getcomposer.org/doc/01-basic-usage.md |
| Composer 2.10 release (Packagist blog) | https://blog.packagist.com/composer-2-10-release/ |
| PHP: supported versions | https://www.php.net/supported-versions.php |
| OWASP Top 10 CI/CD Security Risks | https://owasp.org/www-project-top-10-ci-cd-security-risks/ |
| OpenSSF Scorecard checks | https://github.com/ossf/scorecard/blob/main/docs/checks.md |
| CISA and NSA: Defending CI/CD environments | https://cisa.gov/news-events/alerts/2023/06/28/cisa-and-nsa-release-joint-guidance-defending-continuous-integrationcontinuous-delivery-cicd |

Added in the second pass, all checked 2026-10-27. "Read" means the page itself was fetched. "Summary" means only a search
summary was read, so treat the details as less certain.

| Title | URL | How read |
|---|---|---|
| GitLab: protected tags | https://docs.gitlab.com/user/project/protected_tags/ | Read |
| GitLab: pipeline secret detection | https://docs.gitlab.com/user/application_security/secret_detection/pipeline/ | Read |
| GitLab: Code Owners | https://docs.gitlab.com/user/project/codeowners/ | Read |
| GitLab patch release 19.4.2, 19.3.5, 19.2.8 | https://docs.gitlab.com/releases/patches/patch-release-gitlab-19-4-2-released/ | Read |
| git.wayne.edu help page (edition check) | https://git.wayne.edu/help | Read |
| Composer: config (audit and policy) | https://getcomposer.org/doc/06-config.md | Read |
| Composer releases (GitHub) | https://github.com/composer/composer/releases | Read |
| Packagist: an update on Composer and Packagist supply chain security | https://blog.packagist.com/an-update-on-composer-packagist-supply-chain-security | Read |
| The Hacker News: Composer Perforce flaws (April 2026) | https://thehackernews.com/2026/04/new-php-composer-flaws-enable-arbitrary.html | Read |
| Docker: Docker Hub usage and limits | https://docs.docker.com/docker-hub/usage/ | Read |
| Docker Official Image: php (README) | https://github.com/docker-library/docs/blob/master/php/README.md | Read |
| Renovate: Docker digest pinning | https://docs.renovatebot.com/docker/ | Read |
| Renovate: GitLab CI include manager | https://docs.renovatebot.com/modules/manager/gitlabci-include/ | Read |
| Drupal: GitLab CI, a strategy to empower an ecosystem | https://www.drupal.org/drupalorg/blog/gitlab-ci-drupals-strategy-to-empower-a-whole-ecosystem | Read |
| Drupal gitlab_templates: test locally | https://project.pages.drupalcode.org/gitlab_templates/info/test-locally/ | Read |
| Campus Technology: DOJ extends Title II deadline | https://campustechnology.com/articles/2026/04/27/doj-extends-deadline-for-ada-title-ii-compliance.aspx | Read |
| StepSecurity: tj-actions breach | https://www.stepsecurity.io/blog/when-changed-files-changed-everything-our-black-hat-2025-presentation-on-the-tj-actions-supply-chain-breach | Summary |
| Orca: tj-actions/changed-files compromised | https://orca.security/resources/blog/github-action-tj-actions-changed-files-compromised/ | Summary |
| Semgrep: Shai-Hulud second wave | https://semgrep.dev/blog/2025/digging-for-secrets-sha1-hulud-the-second-coming-of-the-npm-worm | Summary |
| Better Stack: Shai-Hulud | https://betterstack.com/community/guides/scaling-nodejs/shai-hulud-attack/ | Summary |

Pages that were fetched again and re-checked without change: GitLab components, inputs, includes, pipeline security,
variables, job token, Runner security, caching, merge request pipelines, Code Quality, pipeline execution policies,
dependency proxy and the YAML reference; the OWASP CI/CD Top 10 list; php.net supported versions; Composer download,
CLI and the Packagist Composer 2.10 post. The GitLab includes page shows examples with `ref: main` and gives no pinning
advice, which is why 1.1 relies on the pipeline security and components pages instead. Not read: the NVD records for the
Composer and tj-actions CVEs, the Federal Register text of the DOJ rule, and any GitLab Runner release notes.

Stack design decisions and notes used for tagging: the enforcement-points decision, the instance-runner case, the stack
objectives, the first-repos plan, the GitLab CI components research, the Preflight repo and the PROCTOR repo.

## Second pass (2026-10-27)

A second research pass the same day, aimed at what the first pass missed. The templates were read as they stand in the
main checkout. Another worker is changing them on a separate branch, so tags in this pass may need a re-check after that
branch merges.

Added (15 new practices): 1.6, 1.7, 1.8, 2.9, 2.10, 2.11, 3.5, 3.6, 4.10, 4.11, 4.12, 5.5, 6.4, 6.5 and 7.4, plus 19 new
items in the backlog (25 to 43). All the new practices are tagged `Not yet` except 7.4, which is `Documented`. Practices 1.6, 1.7, 4.11 and 4.12
are the most important for the stack's PHP and Vue paths.

Practices that gained new detail but kept their tag: 1.1, 2.1, 2.2, 2.8, 3.1, 3.4, 4.1, 4.2, 4.4, 4.8, 4.9, 5.1, 5.2, 5.3,
6.2, 6.3, 7.2.

Corrected:

- 1.2: the first pass credited the GitLab components page for tag protection. That page covers protected branches only.
  Tag protection comes from the protected tags page, which says "accidental update or deletion" and does not promise a tag
  cannot be moved.
- 4.6: the first pass said Composer fails on abandoned packages "by its configured default". Composer's config page
  supports that (`audit` for abandoned packages defaults to `fail`), but the Packagist 2.10 post reads as report only. The
  conflict is flagged for a fixture test. The first pass also did not mention the `policy` config block or the 2.10.0 exit
  code change.
- 4.9: the first pass argued only for pinning. It now says a pin needs a reviewed bump path, because Composer shipped
  security fixes in April, June, July and August 2026.
- 5.2: "use fine-grained permissions" is now marked unverified, since GitLab's page does not give its status.
- 5.3: added the concrete runner settings the first pass left out.
- Top note: git.wayne.edu showing GitLab Community Edition was confirmed, and the missing version number is now a stated
  unknown.

Claims from the first pass that were checked and held: PHP 8.2 EOL on 2026-12-31 and 8.3 past active support; the 200
permutation matrix limit; `posix_escape` is best effort; Code Quality tiers; Code Owners and pipeline execution policies are
not on Community Edition; protected and unprotected cache separation; the Composer 2.10 release; the SHA and tag
reference order; the stub `bin/proctor`; and the missing `release` job.

Not verified in this pass: whether `component:` includes pinned by SHA survive a Catalog unpublish; whether Renovate
updates component includes; whether secret detection runs on Community Edition; the GitLab version on git.wayne.edu; the
PHP 8.6 release date; whether `gitlab-ci-local` supports components; and the tj-actions and Shai-Hulud details beyond
search summaries.

Injected instructions: none were seen in any fetched page or search result.
