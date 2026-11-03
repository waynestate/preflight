---
title: "Updating image pins | Preflight docs"
description: "Every image the components run is pinned by digest, so a repointed tag cannot quietly change what a pipeline executes."
url: https://preflight.apps.wayne.edu/docs/guides/image-pins.html
llms: https://preflight.apps.wayne.edu/llms.txt
generator: Squire agent-ready
---

# Updating image pins[#](https://preflight.apps.wayne.edu/docs/guides/image-pins.html#updating-image-pins)

This page covers the image pins Preflight's components run: why they are digests, how to look one up, and how to change one. Read the pinning rules, look up the new digest, and open a reviewed merge request. Like the aircraft preflight it is named after, the value shows up on the day it catches something.

## Why pins are digests[#](https://preflight.apps.wayne.edu/docs/guides/image-pins.html#why-pins-are-digests)

Every image the components run is pinned by digest (`name:tag@sha256:...`), so a repointed tag cannot quietly change what a pipeline executes. The tag stays in front of the digest so a diff still reads like a version bump.

Note

The php-test matrix is the one exception. Its PHP images are tag-pinned on purpose, so those jobs run on the newest PHP patch release; every other component image is digest-pinned.

## Look up the digest[#](https://preflight.apps.wayne.edu/docs/guides/image-pins.html#look-up-the-digest)

To look up the digest for an image:

```sh
docker buildx imagetools inspect <image>:<tag>
```

Use the top-level `Digest:` line (the multi-arch index digest), not a per-platform one. Without `buildx`, `docker manifest inspect -v <image>:<tag>` shows the same index digest.

## Change a pin[#](https://preflight.apps.wayne.edu/docs/guides/image-pins.html#change-a-pin)

Pins change only through a reviewed merge request.

## Related[#](https://preflight.apps.wayne.edu/docs/guides/image-pins.html#related)

- [Template lint](https://preflight.apps.wayne.edu/docs/guides/template-lint.html): the unsafe CI patterns `composer ci` scans for before the fixture tests.
- [Shared conventions](https://preflight.apps.wayne.edu/docs/reference/conventions.html): Composer vendor, license, PHP floor and JavaScript installs.
