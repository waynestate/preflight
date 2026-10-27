# PREFLIGHT best practices

Status: draft, checked against sources on 2026-10-27. Applies to the PREFLIGHT components `proctor`, `php-test` and
`composer-audit` at the state of the repo on that date (no release tagged yet).

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

---

## 1. Distributing components

### 1.1 Pin every include to a full commit SHA or a protected release tag
Use a 40-character SHA, or a release tag you control. Never use `~latest`, a branch name or a bare partial version in a
real pipeline.

Why: a tag or branch can move; a SHA cannot.

Sources: [GitLab: CI/CD components, versions](https://docs.gitlab.com/ci/components/);
[GitLab: pipeline security, includes](https://docs.gitlab.com/ci/pipeline_security/);
[OpenSSF Scorecard: Pinned-Dependencies](https://github.com/ossf/scorecard/blob/main/docs/checks.md).

**How the stack holds it: Documented.** The README says to pin a SHA until `0.1.0` is cut. PROCTOR's own
`.gitlab-ci.yml` pins a full SHA, with a comment against `~latest`. Nothing checks an app's includes.

### 1.2 Protect the component project's default branch and release tags
Only maintainers merge to the default branch, force pushes are blocked, and release tags are protected.

Why: whoever can move what a pinned tag points to controls every pipeline that includes it.

Sources: [GitLab: components, security](https://docs.gitlab.com/ci/components/);
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

**How the stack holds it: Documented.** Objectives rule 6 (versioned promises) covers it for the stack. There is no
contract file for the inputs and no test that would catch a rename.

### 1.5 Know that components work only inside one GitLab instance
A component can be used only by projects on the same instance. Another instance needs a mirror.

Why: it decides where PREFLIGHT and the apps that use it must live.

Sources: [GitLab: components, cross-instance access](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** The README has a "Same instance only" section. Until git.wayne.edu has an
instance runner, PREFLIGHT and each app must be on or mirrored to GitLab. See `design/instance-runner-case.md`.

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

### 2.2 Constrain inputs that reach a shell
Use `options` or `regex` on inputs that are placed into `script` lines. Quote them. Do not rely on escaping.

Why: GitLab calls `posix_escape` best effort and says to use `type`, `regex` or `options` for untrusted values.

Sources: [GitLab: CI/CD inputs, guidance](https://docs.gitlab.com/ci/inputs/);
[OWASP CICD-SEC-4 Poisoned Pipeline Execution](https://owasp.org/www-project-top-10-ci-cd-security-risks/).

**How the stack holds it: Not yet.** `working_dir`, `test_command` and `proctor_command` are free strings placed in
`script`. `cd $[[ inputs.working_dir ]]` is not quoted. The values come from the app's own author, so the risk is low,
but `proctor_command` is also how an app could drop `--policy` or add `--today`.

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

---

## 3. What a shared template cannot force

### 3.1 Say plainly that an app can override, skip or delete an included job
State it in the docs, and measure adoption instead of assuming it.

Why: the main `.gitlab-ci.yml` is merged over included jobs, and an app can simply not include PREFLIGHT.

Sources: [GitLab: includes, merge behaviour](https://docs.gitlab.com/ci/yaml/includes/);
[GitLab: pipeline execution policies (Ultimate)](https://docs.gitlab.com/user/application_security/policies/pipeline_execution_policies/).

**How the stack holds it: Documented.** ADR-0002 names the CI gate as point (c) and Fleet as point (e), which shows
who skips CI. ROLLCALL is not built, so nothing reports skipped or weakened pipelines today.

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

**How the stack holds it: Not yet.** The README has no `workflow:rules` example, and the components leave `rules` unset.

---

## 4. The supply chain inside the jobs

### 4.1 Pin container images by digest, and update the pin through review
`php:8.4-cli` and `composer:2` are tags, and a publisher can repoint a tag.

Why: a pinned digest gives the same image every run. Without an update process, a pin also freezes security fixes.

Sources: [GitLab: pipeline security, Docker images](https://docs.gitlab.com/ci/pipeline_security/);
[Docker: build best practices, pin base image versions](https://docs.docker.com/build/building/best-practices/);
[OpenSSF Scorecard: Pinned-Dependencies](https://github.com/ossf/scorecard/blob/main/docs/checks.md).

**How the stack holds it: Not yet.** The defaults are `php:8.4-cli`, `composer:2` and `php:${PHP_VERSION}-cli`, none
pinned by digest.

### 4.2 Use images the instance controls, and match what Citadel runs
Pull through a registry or proxy under WSU's control, and test on the image family that deploys.

Why: Docker Hub rate limits and tag changes can fail a pipeline, and a Debian `php:*-cli` image can differ from the
deploy image in extensions and settings.

Sources: [GitLab: dependency proxy for container images (all tiers)](https://docs.gitlab.com/user/packages/dependency_proxy/);
[Docker: build best practices](https://docs.docker.com/build/building/best-practices/).

**How the stack holds it: Not yet.** `design/instance-runner-case.md` says tests should use Citadel's own images. The
templates use Docker Hub images.

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

### 4.9 Name the version of every tool you download
Install a named Composer release, not whatever is newest.

Why: pinned tools make a run repeatable, and Composer's audit behaviour has changed between releases.

Sources: [GitLab: pipeline security, shell tools](https://docs.gitlab.com/ci/pipeline_security/);
[Composer: download, versioned releases with checksums](https://getcomposer.org/download/).

**How the stack holds it: Not yet.** The installer fetches the latest Composer, and `composer-audit` uses the moving
`composer:2` tag.

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

### 5.2 Limit what the job token can reach
Keep the project's CI/CD job token allowlist short. Add a project only for real cross-project access. Use fine-grained
permissions where they fit.

Why: a leaked job token acts with the triggering user's access.

Sources: [GitLab: CI/CD job token](https://docs.gitlab.com/ci/jobs/ci_job_token/).

**How the stack holds it: Not yet.** It matters when private packages (the planned Pantry registry) need a token. No
document sets the rule.

### 5.3 Use ephemeral, isolated, non-privileged runners
Prefer a Docker executor without privileged mode, one job per fresh environment, and no shell executor shared by
projects.

Why: any Developer can run code on a shared runner, and a non-ephemeral one can leak between projects.

Sources: [GitLab Runner: security](https://docs.gitlab.com/runner/security/);
[CISA and NSA: Defending CI/CD environments](https://cisa.gov/news-events/alerts/2023/06/28/cisa-and-nsa-release-joint-guidance-defending-continuous-integrationcontinuous-delivery-cicd).

**How the stack holds it: Documented.** `design/instance-runner-case.md` expects a Docker executor and leaves capacity,
maintenance and limits to ops. Nothing states "non-privileged" or "ephemeral".

### 5.4 Decide which hosts a job may reach
List what jobs need: the package registry, npm, Docker Hub or a proxy, the Composer installer host, the Debian mirror
that `apt-get` uses, and the advisory source.

Why: network limits reduce what a bad job can send out.

Sources: [GitLab Runner: security, network segmentation](https://docs.gitlab.com/runner/security/).

**How the stack holds it: Documented.** The instance runner case lists network access as an open question for ops.

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

### 6.3 Test on every version the app claims to support
The matrix creates one job per version, up to 200 combinations.

Why: a constraint of `^8.2` is a promise about 8.2, 8.3, 8.4 and 8.5.

Sources: [GitLab: CI/CD YAML, `parallel:matrix`](https://docs.gitlab.com/ci/yaml/).

**How the stack holds it: Checked.** `php-test` creates one job per entry through `parallel:matrix`. The first GitLab
pipeline ran it on 8.2, 8.3, 8.4 and 8.5.

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

### 7.3 Use the stack's own projects as the first users
Each stack repo includes PREFLIGHT, pinned.

Why: the people who write the components feel their faults first.

Sources: [GitLab: components, testing](https://docs.gitlab.com/ci/components/).

**How the stack holds it: Documented.** PROCTOR and CREED include `php-test` and `composer-audit` at a pinned SHA.
WayneUI's pipeline has never run, because git.wayne.edu has no runner.

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

Internal design documents used for tagging: ADR-0002, `design/instance-runner-case.md`, `design/objectives.md`,
`design/first-repos.md`, `research/gitlab-ci-components.md`, the PREFLIGHT repo and the PROCTOR repo.
