---
title: The inputs contract
description: What a Preflight pin promises your includes, where that promise is written down, and how to see what moved between two tags.
---

# The inputs contract

Your app's `include:` lines lean on names: `php_versions`, `working_dir`, a job called `php-test` that your own
`.gitlab-ci.yml` may extend. This page says what Preflight promises about those names, where the promise is written
down, and how to read what changed before you move a pin. A pilot reads the weight and balance sheet before takeoff,
not after the wheels leave the runway.

## What the contract holds

[`contract/inputs.json`](https://git.wayne.edu/enterprise-apps/preflight/-/blob/main/contract/inputs.json) lists every
component in `templates/`, and for each one:

- every input, in template order, with its `type`, its `default` (when it has one) and its `regex` (when the
  template limits the value);
- every job the component adds, by name (php-test adds `php-test`, and `php-test-advisory` when
  `php_advisory_version` is set).

An entry looks like this (php-test, abridged):

```json
"php-test": {
  "inputs": [
    { "name": "php_versions", "type": "array", "default": ["8.3", "8.4", "8.5"] },
    { "name": "php_advisory_version", "type": "string", "default": "", "regex": "^$|^[0-9]+\\.[0-9]+([.-][0-9A-Za-z]+)*$" },
    { "name": "test_command", "type": "string", "default": "vendor/bin/phpunit" },
    { "name": "working_dir", "type": "string", "default": ".", "regex": "^(\\.|[A-Za-z0-9_-][A-Za-z0-9._/-]*)$" }
  ],
  "jobs": ["php-test", "php-test-advisory"]
}
```

## How Preflight holds itself to it

The templates cannot drift from the file. Two checks compare them on every Preflight pipeline:

- `tests/ComponentsContractTest.php`, a PHPUnit suite that `composer ci` runs. It parses every template and fails on
  any difference, naming the component and the input or job that was added, removed or changed, and it says that a
  rename is a breaking change.
- `tests/check-contract.sh` and its `.ps1` twin, in the `contract` job, which make the same comparison and also
  reject any top-level key in a template that is not one of its jobs (no `default:`, `variables:` or `workflow:`
  leaking into your pipeline).

The docs are held to the same file. `tests/DocsInputTablesTest.php`, in the same PHPUnit suite, reads the input table
for every component in the README, in the [components reference](../reference/components.md) and in the component's
own guide, and fails when a table is missing, leaves an input out, lists one the component no longer has, or gives it
a different type or default. A new input reaches a tag only with its row in all three.

When a change to the surface is made on purpose, the same commit rewrites the file with `composer contract:update`,
so the change shows up in review as a diff of `contract/inputs.json`, not as a surprise in your pipeline.

## What that means for your pin

- **Renames and removals are announced.** An input or job is renamed or removed only in a release whose section in
  [Upgrading](../upgrading.md) lists it under Breaking. Before 1.0, Preflight treats the minor number as the major
  one: breaking changes land in a new minor (0.3 to 0.4), and a patch (0.3.0 to 0.3.1) keeps every input, default and
  job name.
- **A tighter `regex` counts as breaking.** A value your include used to pass can stop passing; 0.4.0's Composer floor
  on `composer_version` is the example, and its Upgrading section says so.
- **Defaults move, in the open.** Pinned image digests are defaults too, and Renovate moves them between releases.
  If your include leaves an input unset, you get the new default when you move the pin; the contract diff shows each
  one.
- **Your own job overrides keep working** as long as the job name is in the contract. Overriding a job by a name
  that is not there (an internal helper, a hidden `.key`) is not covered.

## See what moved between two tags

From a clone of Preflight, diff the contract between the tag you pin and the one you are moving to:

```
git diff 0.4.0 0.5.0 -- contract/inputs.json
```

From 0.4.0 to 0.5.0 that shows the new `npm-audit` entry, the `composer_version` default on php-test and proctor
moving from 2.10.3 to 2.11.1, and every Composer `image` default moving to `composer:2.11.1`: one new component and
defaults that moved in the open, nothing renamed or removed. It also shows the renovate `dry_run` pattern, which the
template already enforced in 0.4.0 and the contract now records. From 0.3.1 to 0.4.0 the same command shows
proctor's new `git_depth` input, php-test's `php_advisory_version` input and its `php-test-advisory` job, and the
Composer floor (`regex`) on both components' `composer_version`. Every line of that diff should have a matching line
in the version's Upgrading section; if one does not, open an issue.

## Related

- [Upgrading](../upgrading.md): what each release changed, and the steps to move a pin.
- [Components](../reference/components.md): every component, with its inputs and defaults.
- [Include a component twice](include-twice.md): the `job_name` input every component takes.
- [Local checks](../reference/local-checks.md): `composer test`, `composer contract:update` and the rest of the scripts.
