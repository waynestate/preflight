# package-publish-nocomposer

Fixture for `tests/check-package-publish-fails.sh`: a project root without a
`composer.json`, so the package-publish component's name guard must fail the
release before it reaches the registry.
