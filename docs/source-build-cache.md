# Source build caches

AkuBrowser build and check wrappers share compiler and package download caches. The default cache root is build-cache under the nearest existing ancestor SharedTemp directory. If no ancestor SharedTemp exists, the resolver uses a repository-local SharedTemp/build-cache directory.

A local ignored .cache/source-build-cache.json file may select another root with schemaVersion 1 and an absolute root path. Process environment values GOCACHE, GOMODCACHE, and npm_config_cache take precedence for their matching cache. The macOS shell wrappers resolve the same paths through the Node helper.

A relative npm cache override remains relative. The macOS runtime wrapper rebases it for the Bridge working directory so npm uses the same location selected from the caller's working directory. Existing absolute overrides remain unchanged.

Go scratch files use a unique project-local .cache/source-build-temp directory for each run unless GOTMPDIR is supplied by the caller. The wrappers restore cache, temp, and Git prompt environment values in a finally or exit cleanup path. Git terminal and credential prompts are disabled only for the wrapper process while Go operations run.
