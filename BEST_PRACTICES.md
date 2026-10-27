# PREFLIGHT best practices

Status: draft, checked against sources on 2026-10-27, with a second research pass the same day (see "Second pass
(2026-10-27)" near the end). Applies to the PREFLIGHT components `proctor`, `php-test` and `composer-audit` at the state
of the repo on that date (no release tagged yet).

## What this covers

PREFLIGHT is a set of GitLab CI/CD components that every stack project and WSU app includes with
`include: component:`. Today it has three: `php-test` (PHP versions through `parallel:matrix`), `composer-audit` and
`proctor`. Accessibility and contract suites come later.

This guide is for two groups:

- **WSU developers** who add PREFLIGHT to an app's `.gitlab-ci.yml`.
- **PREFLIGHT maintainers** who write, test and release the components.

It covers how to write and release components, how to keep a pipeline safe, and where a shared template can and cannot
force a standard. Each practice says what to do, why, where the idea comes from, and how the stack holds it today.

PHP that has reached end of life is not supported, and PREFLIGHT does not test it.

### The four tags

| Tag | Meaning |
|---|---|
| `Enforced` | Code makes the bad outcome impossible, or the build fails. The entry names what. |
| `Checked` | PROCTOR or CI warns or fails. The entry names the check. |
| `Documented` | Written down only. Nothing fails if it is ignored. |
| `Not yet` | A gap. Neither code nor text covers it today. |

Tags come from the PREFLIGHT and PROCTOR repos and the stack design documents as read on 2026-10-27. Where a design
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

**How the stack holds it: Documented.** The README says to pin a SHA until `0.1.0` is cut. PROCTOR's own
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

**How the stack holds it: Not yet.** The project settings are not recorded in the repo or in a design document. Write
them down and check them.

### 1.3 Publish to the CI/CD Catalog with a semantic-version tag and a release job
The catalog needs a root `README.md`, a project description, components under `templates/`, and a job that uses the
`release` keyword on a tag. Run the tests before the release job.

Why: the catalog gives typed discovery and lets consumers pin an exact or partial version.

Sources: [GitLab: components, publishing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Not yet.** The layout is right (`templates/<name>/template.yml`, a README). There is no
`release` job in `.gitlab-ci.yml` and no tag. The README examples use `@0.1.0`, which does not resolve yet.

### 1.4 Keep inputs and job names stable inside a major version
Do not rename an input, change its type, or rename a job in a minor release.

Why: consumers pin a range such as `@1`, and a rename breaks them without warning.

Sources: [GitLab: components, partial semver](https://docs.gitlab.com/ci/components/);
[GitLab: component examples, versioning](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Checked.** `contract/inputs.json` lists each component's inputs (name, type, default) and
job names. `tests/check-contract.sh` and `tests/check-contract.ps1` compare the templates with it on every pipeline,
so a renamed input or job, a changed type or a changed default fails the `contract` job.

### 1.5 Know that components work only inside one GitLab instance
A component can be used only by projects on the same instance. Another instance needs a mirror.

Why: it decides where PREFLIGHT and the apps that use it must live.

Sources: [GitLab: components, cross-instance access](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** The README has a "Same instance only" section. Until git.wayne.edu has an
instance runner, PREFLIGHT and each app must be on or mirrored to GitLab. See `design/instance-runner-case.md`.

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

**How the stack holds it: Not yet.** The README says to pin a SHA until `0.1.0` exists, but no release note format
records the SHA, and nothing says what to do after `0.1.0` is cut.

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

**How the stack holds it: Not yet.** No bump process or tool is documented for PREFLIGHT or for the apps that include it.

### 1.8 Say how a component is retired
Before removing a component or turning off its Catalog toggle, announce it and keep the old tag working for a stated period.

Why: GitLab says that turning off the CI/CD Catalog resource toggle deletes the Catalog metadata for the project and its
published versions, and that republishing needs a new release. The docs do not say whether `component:` includes pinned
by SHA keep working afterwards. That is unverified.

Sources: [GitLab: components, unpublishing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Not yet.** There is no deprecation or removal policy in the repo or the design documents.

---

## 2. Writing a component

### 2.1 Declare typed inputs with a description and a default
Every setting is an input with a type, a description and a sensible default. Replace a whole YAML value with an input so
it keeps its type (an array feeds `parallel:matrix`, a boolean feeds `allow_failure`).

Why: GitLab refuses undeclared inputs and checks types when the pipeline is created, and inputs cannot change during
the run.

Sources: [GitLab: CI/CD inputs](https://docs.gitlab.com/ci/inputs/);
[GitLab: component examples](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Enforced.** All three templates use `spec:inputs` with types, descriptions and defaults.
GitLab rejects a wrong type or an unknown input at pipeline creation. The first pipeline on GitLab passed all six jobs
with the array input.

Second pass, limits to design around: GitLab's inputs page says a pipeline can take up to 20 inputs (it does not say
whether that counts per include, so check on the real instance before adding many), a string that uses an input must be
under 1 MB, and an interpolation block must be under 1 KB. GitLab also recommends inputs over pipeline variables since 17.7
(see 3.5).

### 2.2 Constrain inputs that reach a shell
Use `options` or `regex` on inputs that are placed into `script` lines. Quote them. Do not rely on escaping.

Why: GitLab calls `posix_escape` best effort and says to use `type`, `regex` or `options` for untrusted values.

Sources: [GitLab: CI/CD inputs, guidance](https://docs.gitlab.com/ci/inputs/);
[OWASP CICD-SEC-4 Poisoned Pipeline Execution](https://owasp.org/www-project-top-10-ci-cd-security-risks/).

**How the stack holds it: Not yet.** `working_dir`, `test_command` and `proctor_command` are free strings placed in
`script`. `cd $[[ inputs.working_dir ]]` is not quoted. The values come from the app's own author, so the risk is low,
but `proctor_command` is also how an app could drop `--policy` or add `--today`.

Second pass: the GitLab inputs page was re-read and the first pass is right. It says "Do not rely on `posix_escape` for
security purposes with untrusted input values". It recommends `number` and `boolean` types, `regex` and `options` for
untrusted values. New point: from GitLab 19.0 an array input with `options` makes the pipeline refuse to start if any
array item is not in the list. That would let `php_versions` accept only versions the policy lists (see 6.2), but it
depends on the instance running 19.0 or later, which is unknown. GitLab's pipeline security page also says to avoid
variables in container references because they can be changed to point at a malicious image. `php-test` builds its image
from the matrix variable (`php:${PHP_VERSION}-cli`). The value comes from the `php_versions` input, so the risk is low,
but constraining that input closes it.

### 2.3 Keep settings in the job, and give each component one job purpose
Put `image` and other keys inside the job, not at the top level of the template. One component does one thing.

Why: global keys leak into the consuming pipeline.

Sources: [GitLab: component examples](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Documented.** All three templates follow it, by convention. No lint fails if a template adds
a global key.

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

**How the stack holds it: Not yet.** The jobs are named `proctor`, `php-test` and `composer-audit`, fixed.

### 2.6 Offer a way to weaken a gate only where it is meant
`composer-audit` has no `allow_failure` input, on purpose. `proctor` has one.

Why: every switch is a way to ship around the standard.

Sources: [GitLab: CI/CD YAML, `allow_failure`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Documented.** A comment in the `composer-audit` template says advisories must fail. The
difference between the two components is not explained in the README, and an app can override either one anyway (see 3.1).

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
`reports: codequality: gl-code-quality-report.json`. Code Quality is shown in the merge request Reports tab on every
tier; the pipeline tab needs Premium and the diff view needs Ultimate.

Second pass: tiers re-checked and correct. One addition: GitLab deprecated its built-in CodeClimate-based Code Quality
template in 17.3 and plans to remove it in 19.0, and prefers importing a tool's own report. PREFLIGHT uses the report
artifact, not the template, so it is not affected. The report must be a single JSON array with no byte order mark, and
each entry needs `description`, `check_name`, `fingerprint`, `location.path` (no leading `./`), a line number and a
`severity` of `info`, `minor`, `major`, `critical` or `blocker`. PROCTOR's output should be tested against those rules.

### 2.9 Set a timeout, and let superseded pipelines be cancelled
Give each job a `timeout` and `interruptible: true` where a newer push makes the old run pointless.

Why: a hung `apt-get` or `composer install` holds a runner, and runners are the scarce part of a shared instance.
GitLab's `interruptible` defaults to `false`. The `timeout` keyword cannot be set in `default`, so each job needs its own.
A job timeout cannot exceed the runner's timeout.

Sources: [GitLab: CI/CD YAML, `timeout` and `interruptible`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Not yet.** None of the three templates sets either keyword. Whether an old pipeline is actually
cancelled also needs `workflow:auto_cancel` in the app's own file.

### 2.10 Make every job image an input
`proctor` and `composer-audit` already take `image`. `php-test` builds its image from `php_versions` and has no way to
swap the image family.

Why: GitLab's component examples expose the image as an input, and the stack needs to move to WSU-controlled or
Citadel-matching images later (see 4.2) without a new major version.

Sources: [GitLab: component examples, inputs for image versions](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Not yet.** Two of three components comply. `php-test` hard-codes `php:${PHP_VERSION}-cli`.

### 2.11 Print which component version ran
Use `spec:component` and `$[[ component.sha ]]` or `$[[ component.version ]]` to write the component's own version into
the job log.

Why: when a job misbehaves, the log should say which release of PREFLIGHT produced it. GitLab's docs say `spec:component`
exposes `name`, `sha`, `version` and `reference`, was beta in 18.6 and became GA in 18.7.

Sources: [GitLab: components, `spec:component`](https://docs.gitlab.com/ci/components/);
[GitLab: component examples, versioning with component context](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Not yet.** No template uses it. It needs GitLab 18.7 or later, which is unconfirmed for
git.wayne.edu.

---

## 3. What a shared template cannot force

### 3.1 Say plainly that an app can override, skip or delete an included job
State it in the docs, and measure adoption instead of assuming it.

Why: the main `.gitlab-ci.yml` is merged over included jobs, and an app can simply not include PREFLIGHT.

Sources: [GitLab: includes, merge behaviour](https://docs.gitlab.com/ci/yaml/includes/);
[GitLab: pipeline execution policies (Ultimate)](https://docs.gitlab.com/user/application_security/policies/pipeline_execution_policies/).

**How the stack holds it: Documented.** ADR-0002 names the CI gate as point (c) and Fleet as point (e), which shows
who skips CI. ROLLCALL is not built, so nothing reports skipped or weakened pipelines today.

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

**How the stack holds it: Not yet.** Protected branches with required merge requests are available on every tier. Code
owner approval is Premium or Ultimate, so it is not available on Community Edition. No PREFLIGHT text recommends
settings for app repos.

### 3.3 Detect pipelines that skip or weaken PREFLIGHT
A check or a fleet report should flag an app with no PREFLIGHT include, an unpinned include, `allow_failure: true` on a
gate, or a missing `proctor` job.

Why: a standard that nobody can see being skipped is not a standard.

Sources: [OWASP CICD-SEC-1 Insufficient Flow Control Mechanisms](https://owasp.org/www-project-top-10-ci-cd-security-risks/);
[OpenSSF Scorecard: SAST](https://github.com/ossf/scorecard/blob/main/docs/checks.md) (a check for whether analysis
runs at all).

**How the stack holds it: Not yet.** PROCTOR does not read `.gitlab-ci.yml`. ROLLCALL's "apps with CI" number is a plan.

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

**How the stack holds it: Not yet.** The components use inputs, which is right. No text tells app owners to restrict
pipeline variables.

### 3.6 Keep untrusted code away from secrets and from the install step
Do not run fork merge request pipelines with protected variables. Review a fork's `.gitlab-ci.yml` before running it.

Why: GitLab says a fork's merge request pipeline runs the fork's configuration, and that malicious code "can compromise
both masked and protected variables". Protected variables and runners reach a merge request pipeline only if both
branches are protected, the user has push or merge access to the target and both branches are in the same project. Fork
pipelines never get that access. This also matters for Composer: the April 2026 Composer flaws (see 4.4) are triggered
by a hostile `composer.json`, which is exactly what a contributed branch can carry.

Sources: [GitLab: merge request pipelines](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/);
[GitLab: CI/CD variables](https://docs.gitlab.com/ci/variables/).

**How the stack holds it: Not yet.** The three templates use no secrets, which limits the harm. Nothing documents the rule.

---

## 4. The supply chain inside the jobs

### 4.1 Pin container images by digest, and update the pin through review
`php:8.4-cli` and `composer:2` are tags, and a publisher can repoint a tag.

Why: a pinned digest gives the same image every run. Without an update process, a pin also freezes security fixes.

Sources: [GitLab: pipeline security, Docker images](https://docs.gitlab.com/ci/pipeline_security/);
[Docker: build best practices, pin base image versions](https://docs.docker.com/build/building/best-practices/);
[OpenSSF Scorecard: Pinned-Dependencies](https://github.com/ossf/scorecard/blob/main/docs/checks.md).

**How the stack holds it: Enforced.** The `proctor` and `composer-audit` image defaults carry a digest
(`php:8.4-cli@sha256:...` and `composer:2@sha256:...`), and the README's "Updating image pins" says how to move them.
The exception is `php-test`: its matrix image `php:${PHP_VERSION}-cli` is still a tag, because each version would need its own digest.

Second pass: GitLab's pipeline security page says "Always use SHA digests for Docker images". Renovate documents the
usual way to live with that: keep the tag and add the digest (`image:tag@sha256:...`), and let a bot open a change when the
digest moves. Be careful with automerge settings that skip review (see 1.7). A digest on a matrix image
(`php:${PHP_VERSION}-cli`) needs one digest per version, so the matrix would need to carry the digest too.

### 4.2 Use images the instance controls, and test on the image family of the target you deploy to
Pull through a registry or proxy under WSU's control, and test on the image family of the target you deploy to.
Citadel's images are the `citadel` target, and the official `php` images are the default for raw Docker, OpenShift
and Coolify.

Why: Docker Hub rate limits and tag changes can fail a pipeline, and a Debian `php:*-cli` image can differ from the
deploy image in extensions and settings.

Sources: [GitLab: dependency proxy for container images (all tiers)](https://docs.gitlab.com/user/packages/dependency_proxy/);
[Docker: build best practices](https://docs.docker.com/build/building/best-practices/).

**How the stack holds it: Partially.** The templates use the official `php` images from Docker Hub, the default for
raw Docker, OpenShift and Coolify. For the `citadel` target, the jobs should run on Citadel's own images; the
templates do not switch on the target yet.

Second pass, rate limits re-checked in Docker's docs: unauthenticated pulls are limited to 100 per 6 hours per IPv4
address or IPv6 /64 subnet, and free authenticated users to 200 per 6 hours. A shared instance runner usually sits behind
one address. A default pipeline pulls about six images (four PHP versions, `composer:2`, `php:8.4-cli`), so roughly
sixteen cold pipelines per six hours would use up the unauthenticated limit for the whole runner. That is arithmetic
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

**How the stack holds it: Not yet.** The templates use `composer install`, which is right. They do not pass
`--no-plugins` or `--no-scripts`, and the `proctor` job runs the app's install before the check. An app on an
old PHP floor cannot be installed on `php:8.4-cli`, so the check may never run for it. The stack's plan is to run
PROCTOR on the source tree without installing the app.

Second pass, why this matters more now: in April 2026 two Composer flaws (CVE-2026-40176, CVSS 7.8, and CVE-2026-40261,
CVSS 8.8) allowed arbitrary command execution as the user running Composer. One is triggered by a `composer.json` that
declares a Perforce repository, and the maintainers say Composer runs the injected commands even when Perforce is not
installed. The other is a shell escaping flaw reachable through a crafted source reference, including from package
metadata served by a malicious repository. Fixed versions are 2.9.6 and 2.2.27. Further security fixes followed in 2.10.1
(2026-06-04), 2.10.2 (2026-07-01) and 2.10.3 (2026-08-27), including a Perforce URL injection (CVE-2026-84361) and a
bin path symlink traversal (CVE-2026-59944). The mitigation advice in the news report is to run Composer only on projects
from trusted sources.
Composer 2.10.0 also began enforcing `allow-plugins` for old lock files. The 2.10.3 and 2.11.0-RC1 details come from the
Composer GitHub releases page, which was read in this pass. The CVE records on NVD were not read.

Sources: [The Hacker News: Composer flaws](https://thehackernews.com/2026/04/new-php-composer-flaws-enable-arbitrary.html);
[Composer releases](https://github.com/composer/composer/releases).

### 4.5 Commit the lock file, and let a check say so
Composer's docs say to commit `composer.lock`. `composer install` with no lock resolves new versions and succeeds.

Why: the template alone would not notice a missing lock.

Sources: [Composer basic usage: the lock file](https://getcomposer.org/doc/01-basic-usage.md).

**How the stack holds it: Checked.** PROCTOR's `lock-committed` fails when the lock is missing. It runs only if the app
includes the `proctor` component, which cannot run yet (see 6.1).

### 4.6 Audit the lock and fail the job
Run `composer audit --locked`. A non-zero exit fails the job. Give the audit no `allow_failure`.

Why: a known vulnerability should stop the merge.

Sources: [Composer CLI: audit](https://getcomposer.org/doc/03-cli.md);
[Composer 2.10 release](https://blog.packagist.com/composer-2-10-release/).

**How the stack holds it: Checked.** The `composer-audit` job fails on Composer's exit code. Composer also fails on
malware and, by its configured default, on abandoned packages, and PROCTOR's own audit check reads only advisories.
The two can disagree. The job uses `composer:2`, a moving tag, so the rules depend on which Composer release the tag
points at.

Second pass, corrections and detail from Composer's current docs:

- Composer 2.10.0 (2026-05-28) changed the `audit` exit code to 0 on success and 1 if anything fails. Earlier releases
  used a different scheme. The CI job only needs "non-zero fails", so nothing breaks, but any script that read the old
  codes must change.
- Composer 2.10 added a `policy` config block for advisories, abandoned packages and malware. It replaces most of the
  `audit` block. `audit` still works as a fallback in 2.10 and is due to warn as deprecated in 2.11. An app that sets
  `config.audit.ignore` today should plan to move it.
- Malware: Composer 2.10 removes flagged versions from resolution and also checks at `composer install`, so a flagged
  version already in a lock file fails the install. Packagist takes the data from Aikido (since March 2026).
- Conflict to resolve by test: Composer's config page lists `policy.abandoned.audit` with default `fail` (and the older
  `audit.abandoned` defaulting to `fail` since Composer 2.7). The Packagist 2.10 post says audit "only reports" abandoned
  packages. The first pass said audit fails on abandoned packages. The config page supports that, the blog wording does
  not, and this pass did not run Composer. Add a fixture with an abandoned package and record the real exit code (see
  7.2).
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

**How the stack holds it: Not yet.** No schedule is documented or provided.

### 4.8 Cache dependencies by lock hash and keep protected and unprotected caches apart
Key the Composer cache on `composer.lock`. Leave GitLab's separation of protected and unprotected caches on.

Why: pipelines run faster, and an unreviewed branch cannot poison the cache that a protected branch uses.

Sources: [GitLab: caching](https://docs.gitlab.com/ci/caching/).

**How the stack holds it: Not yet.** The templates define no cache, so each matrix job downloads all packages again.

Second pass: GitLab appends `-protected` or `-non_protected` to every cache key. Pipelines on protected branches or tags,
and pipelines started by a Maintainer or Owner, get `-protected`. The separation is on by default and GitLab calls it
"a security feature", to be switched off only when every Developer is highly trusted. Use `cache:key:files` on
`composer.lock`. GitLab's page also warns that after a cache clear, unpinned dependencies can pull a newer unreviewed
release. GitLab's page has no PHP or Composer example, so the Composer cache directory setup is not covered by a source.

### 4.9 Name the version of every tool you download
Install a named Composer release, not whatever is newest.

Why: pinned tools make a run repeatable, and Composer's audit behaviour has changed between releases.

Sources: [GitLab: pipeline security, shell tools](https://docs.gitlab.com/ci/pipeline_security/);
[Composer: download, versioned releases with checksums](https://getcomposer.org/download/).

**How the stack holds it: Enforced.** `proctor` and `php-test` install the Composer release named by the
`composer_version` input (default `2.10.3`, which must match `^2\.\d+\.\d+$`), after checking the installer's SHA-384.
`composer-audit` uses a digest-pinned `composer:2` image.

Second pass: this practice pulls two ways, and the guide should say so. A pinned Composer is repeatable, but Composer
shipped security releases on 2026-04 (2.9.6), 2026-06-04 (2.10.1), 2026-07-01 (2.10.2) and 2026-08-27 (2.10.3), and
2.11.0-RC1 (2026-10-22) lists more. Composer 2.2 is a long-term release that gets critical security fixes only, with a
stated minimum maintenance date of 2026-12-31. So pin a version, and move the pin through a reviewed change (see 1.7). Do
not pin and forget. Composer's download page publishes a SHA-256 file and a PGP signature for each versioned `composer.phar`.
The page's own installer example now shows a fixed SHA-384 value and points to `composer.github.io/pubkeys.html` for
cross-checking, while PREFLIGHT fetches `installer.sig` at runtime. The runtime fetch is acceptable (it comes from a
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

**How the stack holds it: Not yet.** The defaults use the bare `cli` tag of the official `php` images, the default for
raw Docker, OpenShift and Coolify. For the `citadel` target, the jobs should run on Citadel's own images; which Debian
release those use is not stated in the documents read for this guide.

### 4.11 Use Composer's malware and advisory blocking, and review lock changes
Run Composer 2.10 or later so flagged versions are refused at install and audit. Review `composer.lock` diffs after any
`update` or `require`.

Why: 2026 had real Composer supply chain incidents. The Packagist team names the `intercom/intercom-php` compromise
(2026-04-30) and the `laravel-lang` credential stealer (2026-05-22), and describes taken-over GitHub accounts and stolen
tokens used to move or add tags. Packagist now imports Aikido malware results (since March 2026) and is making stable
versions immutable. The same post says `composer install` from an existing lock reproduces the locked commit hashes,
while `update` and `require` can rewrite lock entries. It also says a minimum release age (cooldown) policy is designed
but not available yet. Composer 2.10 deprecates falling back from a failed dist download to a source download, because
that could install a version a repository had blocked, and 2.11.0-RC1 removes the `source-fallback` option. The runner
images need `git` today (see the apt line in the templates), so check whether any app depends on the fallback.

Sources: [Packagist: supply chain security update](https://blog.packagist.com/an-update-on-composer-packagist-supply-chain-security);
[Packagist: Composer 2.10 release](https://blog.packagist.com/composer-2-10-release/).

**How the stack holds it: Not yet.** `php-test` and `proctor` install the latest Composer, so they pick up 2.10 behaviour
by accident, and `composer-audit` depends on what `composer:2` points at. Nothing records the rule or tests it.

### 4.12 When a JavaScript component arrives, install from the lock with scripts off
For the Vue paths, a future PREFLIGHT job should use `npm ci`, turn off install scripts by default and allow them only
for named packages, and keep tokens out of the job.

Why: the Shai-Hulud npm worm (second wave, November 2025) moved its payload to `preinstall`, stole CI and cloud
credentials and spread through the victims' accounts. Vendors recommend disabling install scripts in CI. One vendor guide
warns that this alone does not stop every variant, so pair it with short-lived tokens and limited outbound network access
(see 5.4).

Sources: [Semgrep: Shai-Hulud second wave](https://semgrep.dev/blog/2025/digging-for-secrets-sha1-hulud-the-second-coming-of-the-npm-worm);
[Better Stack: Shai-Hulud](https://betterstack.com/community/guides/scaling-nodejs/shai-hulud-attack/). These were read as
search summaries only, so details are unverified.

**How the stack holds it: Not yet.** PREFLIGHT has no JavaScript component. Record the rule before one is written.

---

## 5. Secrets, tokens and runners

### 5.1 Keep secrets out of components and CI files
Components hold no credentials. Where a job needs one, it comes from a masked, hidden and protected variable or an
external secret store, and the component takes it as an input name, not a value.

Why: CI file contents are readable by everyone with repo access, and masking is not a guarantee.

Sources: [GitLab: CI/CD variables](https://docs.gitlab.com/ci/variables/);
[GitLab: pipeline security, secrets](https://docs.gitlab.com/ci/pipeline_security/);
[OWASP CICD-SEC-6 Insufficient Credential Hygiene](https://owasp.org/www-project-top-10-ci-cd-security-risks/).

**How the stack holds it: Not yet.** The three templates use no secrets, which is good. Nothing fails if a later
template adds one, and no secret scan runs on the PREFLIGHT repo.

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

**How the stack holds it: Not yet.** It matters when private packages (the planned Pantry registry) need a token. No
document sets the rule.

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

**How the stack holds it: Documented.** `design/instance-runner-case.md` expects a Docker executor and leaves capacity,
maintenance and limits to ops. Nothing states "non-privileged" or "ephemeral".

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
do, and they disagree on dates, so check GitLab's own advisory and ops' judgement before acting on that advice. Every
PREFLIGHT job depends on this instance being sound, and the guide cannot tell whether git.wayne.edu is patched because its
help page shows no version.

Sources: [GitLab patch release 19.4.2, 19.3.5, 19.2.8](https://docs.gitlab.com/releases/patches/patch-release-gitlab-19-4-2-released/).

**How the stack holds it: Not yet.** Instance patching is outside the PREFLIGHT repo. Record the owner and the schedule in
the instance runner request.

---

## 6. Staying current with the policy

### 6.1 Make the `proctor` component runnable
The default command must work without extra options on a fresh app.

Why: a default that errors teaches developers to ignore the job.

Sources: [GitLab: component examples, defaults](https://docs.gitlab.com/ci/components/examples/).

**How the stack holds it: Not yet.** The default `vendor/bin/proctor check --format=codequality` omits `--policy`, which
PROCTOR requires, so it exits 2. PROCTOR will default to CREED's bundled policy once CREED v0.1.0 is tagged. PROCTOR
and CREED pipelines include only `php-test` and `composer-audit` until then.

### 6.2 Derive the PHP matrix from the policy, and drop end-of-life versions
The tested versions should be those the policy lists as supported, intersected with what the app declares.

Why: a hard-coded list goes stale when a version reaches end of life.

Sources: [PHP supported versions](https://www.php.net/supported-versions.php);
[GitLab: CI/CD YAML, `parallel:matrix`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Not yet.** The default list is `["8.2", "8.3", "8.4", "8.5"]`. PHP 8.2 reaches end of life on
2026-12-31, and PHP 8.3 is already past active support. The floor in the README (`^8.2`) is also a hard-coded value.

Second pass: php.net's supported versions page was re-read on 2026-10-27 and the first pass is correct.

| Branch | Released | Active support ended or ends | Security support ends |
|---|---|---|---|
| 8.2 | 2022-12-08 | 2024-12-31 | 2026-12-31 |
| 8.3 | 2023-11-23 | 2025-12-31 | 2027-12-31 |
| 8.4 | 2024-11-21 | 2026-12-31 | 2028-12-31 |
| 8.5 | 2025-11-20 | 2027-12-31 | 2029-12-31 |

Two consequences. First, 8.2 is still supported today, but only for security fixes and only for another 65 days. The
default list must drop it in a release that ships before 2027-01-01, so apps have time to see it. Second, 8.4 moves to
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

**How the stack holds it: Checked.** `php-test` creates one job per entry through `parallel:matrix`. The first GitLab
pipeline ran it on 8.2, 8.3, 8.4 and 8.5.

The matrix limit of 200 permutations was re-checked in the GitLab YAML reference and is correct.

### 6.4 Add an advisory job for the next PHP release
Run the tests on the next PHP version (a release candidate once one exists) in a job that may fail, so the app learns about
breakage before the version becomes supported.

Why: the Docker Official Image README already lists PHP 8.6 release candidates on 2026-10-27, and the matrix has no early
warning. An advisory job must not become a gate: only a final, supported version belongs in the required matrix.

Sources: [Docker Official Image: php](https://github.com/docker-library/docs/blob/master/php/README.md);
[PHP supported versions](https://www.php.net/supported-versions.php). The tag names for release candidates were not checked.

**How the stack holds it: Not yet.** `php-test` has no input for an advisory version.

### 6.5 Aim the future accessibility component at WCAG 2.1 AA
When PREFLIGHT gets an accessibility suite, use WCAG 2.1 Level AA as the floor, and keep a manual review step.

Why: on 2026-04-20 the US Department of Justice published an interim final rule that moved the Title II web accessibility
compliance dates by one year, to 2027-04-26 for public entities with a population of 50,000 or more and 2028-04-26 for
smaller ones. It did not change the standard, WCAG 2.1 Level AA. A trade press report says covered content includes
public educational institutions' portals, forms, learning management content and websites. Which date applies to WSU
depends on how the university is classified, so ask counsel. One search summary said the extension is being challenged in
federal court. That is unverified. Automated checks find only some failures, so a green job does not prove conformance.

Sources: [Campus Technology: DOJ extends Title II deadline](https://campustechnology.com/articles/2026/04/27/doj-extends-deadline-for-ada-title-ii-compliance.aspx).
The Federal Register text itself was not read in this pass.

**How the stack holds it: Not yet.** The scope note at the top of this guide says accessibility and contract suites come
later. No component, input or text names the standard.

---

## 7. Testing the components

### 7.1 Test each component from the commit under review
Include the component with `$CI_COMMIT_SHA` in the project's own pipeline, against a sample app.

Why: it exercises exactly what will be released.

Sources: [GitLab: components, testing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Checked.** `.gitlab-ci.yml` includes all three components at `$CI_COMMIT_SHA` against
`tests/fixture-app`.

### 7.2 Test the failing cases, and that the expected jobs exist
Each component needs a fixture that must fail it: a failing test, an advisory, a policy violation. A test can also
confirm that the expected job was created.

Why: a component that never fails looks the same as one that works.

Sources: [GitLab: components, testing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Not yet.** The fixture's `bin/proctor` is a stub that prints `[]` and exits 0, so the
`proctor` self-test cannot fail. The fixture has no advisory and no failing test.

Second pass, checked in the main checkout: the stub is still a short shell script that prints `[]` and exits 0, and
the fixture's `composer.json` requires only `php ^8.2` and `phpunit ^11.0`. Add fixtures for an advisory, an abandoned
package and a malware-flagged version too (see 4.6 and 4.11), so each Composer policy result is recorded as a real exit code.

### 7.3 Use the stack's own projects as the first users
Each stack repo includes PREFLIGHT, pinned.

Why: the people who write the components feel their faults first.

Sources: [GitLab: components, testing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** PROCTOR and CREED include `php-test` and `composer-audit` at a pinned SHA.
WayneUI's pipeline has never run, because git.wayne.edu has no runner.

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

1. 6.1: Make the `proctor` default command work (bundled policy), then add it to PROCTOR's and CREED's pipelines.
2. 7.2: Add failing fixtures for each component and replace the stub `bin/proctor` with the real tool.
3. 3.3: Add a check or ROLLCALL report for apps that skip, unpin or weaken PREFLIGHT.
4. 4.1: Pin images by digest and update the pins through reviewed merge requests.
5. 4.4: Run PROCTOR without installing the app, and pass `--no-plugins --no-scripts` where jobs only inspect.
6. 1.3: Add the `release` job, tag `0.1.0`, publish to the Catalog, and fix README examples.
7. 1.2: Record and check the project's branch and tag protection.
8. 6.2: Derive the PHP matrix from the policy, and drop 8.2 by 2027-01-01.
9. 4.9: Pin the Composer version the installer fetches and the `composer-audit` image.
10. 2.2: Add `regex` or `options` to shell-bound inputs and quote `working_dir`.
11. 4.7: Provide a scheduled audit pipeline.
12. 4.2: Use a dependency proxy or Citadel images for job images.
13. 3.2: Recommend branch and CI-file protection for app repos.
14. 3.4: Add a `workflow:rules` example to the README.
15. 2.5: Build job names from an input so one project can include a component twice.
16. 4.8: Add a Composer cache keyed on `composer.lock`.
17. 5.1: Add secret detection to PREFLIGHT's own pipeline.
18. 5.2: Write down the job token allowlist rule for projects that use Pantry.
19. 5.3: State "non-privileged, ephemeral Docker executor" in the runner request.
20. 5.4: Agree the list of hosts jobs may reach.
21. 1.4: Add an inputs contract file and a test that catches a renamed input or job.
22. 2.3 and 2.6: Lint templates for global keys, and explain which components may be weakened.
23. 3.1: Publish the "components do not force" limit in the README.
24. 5.3 and 5.4 and 7.3: Close with the git.wayne.edu instance runner (D-007); WayneUI's pipeline cannot run until then.

Added in the second pass (2026-10-27):

25. 5.5: Get the GitLab and runner versions and the patch schedule from ops, and record them in the instance runner
    request. A critical CI-related GitLab patch shipped on 2026-10-12.
26. 6.2 (updated): Ship a default list without 8.2 before 2027-01-01, and add 8.6 to the policy path when it is released.
27. 4.9 and 4.6 (updated): Pin Composer to a named release with a reviewed bump path, and require 2.9.6 or later (2.10.3 is
    current), because of the April to August 2026 Composer security fixes.
28. 4.6 and 7.2 (updated): Add fixtures for an advisory, an abandoned package and a malware-flagged version, and record
    the real audit exit codes. Settle the conflict on abandoned packages.
29. 1.7: Offer a reviewed bump process (bot or scheduled merge request) for component SHAs and image digests. Test whether
    Renovate handles `component:` includes first.
30. 1.6: Put the commit SHA in every release note and tell apps to pin it.
31. 4.11: Write the stack's rule for Composer malware, advisory and abandoned policy, and require Composer 2.10 or later.
32. 4.10: Name the Debian release in image tags, or match the image family of the target you deploy to.
33. 2.9: Add `timeout` and `interruptible` to each job.
34. 3.4 (updated): Put the `workflow:rules` example in the README, and say it must live in the app's own file.
35. 3.5 and 3.6: Tell app owners to restrict pipeline variables and keep fork merge requests away from secrets.
36. 2.10: Add an `image` input to `php-test`.
37. 7.4: Add a cross-OS local run (Composer scripts first) and test the README's local commands in PowerShell.
38. 6.4: Add an advisory job for the next PHP release.
39. 6.5: Name WCAG 2.1 AA as the floor before the accessibility component is written.
40. 1.8: Write a retirement policy for components, and test whether SHA pins survive a Catalog unpublish.
41. 4.12: Record the install-scripts rule before a JavaScript component is written.
42. 2.11: Print the component version in job logs once the instance runs GitLab 18.7 or later.
43. 5.1 (updated): Test whether GitLab secret detection runs on git.wayne.edu (Community Edition), and add it to PREFLIGHT's
    pipeline if it does.

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

Internal design documents used for tagging: ADR-0002, `design/instance-runner-case.md`, `design/objectives.md`,
`design/first-repos.md`, `research/gitlab-ci-components.md`, the PREFLIGHT repo and the PROCTOR repo.

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
