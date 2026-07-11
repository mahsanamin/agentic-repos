---
alwaysApply: false
---
## Docker Build Cache, Archive, Don't Copy

### Rule

When writing `docker-utils.sh` (or any CI helper that saves build caches from inside a Docker container), the `save-cache` function **must** write a single compressed archive (e.g., `tar.gz`) instead of copying raw directory trees.

### Why

Docker containers typically run as **root**. When a container writes files to a bind-mounted host volume via `cp -r`, every file and directory is owned by root on the host. The CI agent (e.g., Jenkins running as a non-root `jenkins` user) cannot delete these root-owned files. A single archive file can be deleted, but a deeply nested directory tree of root-owned files causes workspace cleanup (`deleteDir()`, `rm -rf`) to fail with `Operation not permitted`, permanently wedging the CI pipeline.

### Correct Pattern

```bash
GRADLE_CACHE_DIR="$HOME/.gradle/caches"
GRADLE_CACHE_ARCHIVE="build-cache/gradle.tar.gz"

function __save_cache {
  mkdir -p "$(dirname "$GRADLE_CACHE_ARCHIVE")"
  GZIP=-n tar -czf "$GRADLE_CACHE_ARCHIVE" \
    --exclude='./modules-2/modules-2.lock' \
    --exclude='./*/plugin-resolution' \
    -C "$GRADLE_CACHE_DIR" .
}
```

### Wrong Pattern

```bash
# BAD: Creates thousands of root-owned files on the host
function __save_cache {
  mkdir -p build-cache/gradle-caches build-cache/gradle-wrapper
  cp -r ~/.gradle/caches/* build-cache/gradle-caches/
  cp -r ~/.gradle/wrapper/* build-cache/gradle-wrapper/
}
```

### When This Applies

- Any `docker-utils.sh` or CI helper script that caches build artifacts (Gradle, Maven, npm, etc.) from inside a Docker container
- Any script using `docker run` with bind-mounted volumes (`-v`) where the container runs as root
