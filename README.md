# Portable Python starter

Copy this directory's contents, including `.github`, to a GitHub repository.
Run **Actions > Build portable Python > Run workflow** and select Python.
Each successful run publishes a GitHub Release containing all files in `dist/`,
including the runtime archive, dependency manifests and SHA256SUMS.
Release tags use `python-<series>-build-<run-number>-<run-attempt>` so reruns
create a new release instead of overwriting earlier output.
The workflow uses the automatic GITHUB_TOKEN with `contents: write`; no personal
access token is needed. Repository or organization policies must allow releases.
The Actions artifact is also retained for 30 days. Release assets are not subject
to that artifact retention period; private repository downloads require access.

The workflow creates Linux x86_64 Python + pip using only conda-forge, with
conda-pack in a separate build environment. It checks installed package origins,
exports exact Conda package URLs, and tests relocation in Debian 9 and 10 without
network access. No internal packages or repository credentials are needed.

The glibc solver baseline is 2.24 and the minimum compatibility target is
Debian 9. Container tests assert glibc 2.24 on Debian 9 and 2.28 on Debian 10.
This compatibility target does not imply ongoing OS security support.
This does not establish compatibility with every kernel 5.4/5.15 machine.
Verify architecture, glibc,
CPU requirements and application behavior on your oldest actual target.
The solver override does not rebuild binaries. The container test is a smoke
test, not a full compatibility certification. If no compatible package set
exists for a selected Python series, resolution must fail rather than raising
the glibc baseline silently. Old container images must remain downloadable;
an image pull failure is a test infrastructure failure, not a compatibility pass.
Docker shares the host kernel, so test the actual 5.4/5.15 kernels separately.
Private pip dependencies installed later must also be tested on this baseline:
CONDA_OVERRIDE_GLIBC does not constrain pip wheel selection or source builds.

## Deployment

Download the Release assets into one directory, or extract the Actions artifact.
Run from that directory and use a new empty destination:

```bash
sha256sum -c SHA256SUMS
mkdir -p /opt/company/runtime-v1
tar -xzf python-3.11-linux-x86_64.tar.gz -C /opt/company/runtime-v1
/opt/company/runtime-v1/bin/python /opt/company/runtime-v1/bin/conda-unpack
/opt/company/runtime-v1/bin/python -V
export PATH="/opt/company/runtime-v1/bin:$PATH"
```

Adjust the archive name for the selected Python series. After conda-unpack,
do not move this directory. Extract the original archive again for another path.

Relocated command entry points may use `/usr/bin/env python3.X`, so prepend
the runtime's `bin` directory to PATH even when invoking a command by absolute
path. For pip, explicitly invoking `bin/python -m pip` also avoids interpreter
lookup through PATH. Services must set their own PATH; they do not inherit an
interactive shell's export. Packages with activation hooks may additionally
require sourcing `bin/activate`.

Install private dependencies in a Debian 9 / glibc 2.24 isolated build
environment, or an equivalent compatible toolchain. Installing on Debian 10
can select wheels or compile extensions requiring glibc 2.28. Test the final
environment on both Debian 9 and 10 after installation:

```bash
/opt/company/runtime-v1/bin/python -m pip install \
  -i https://bytedpypi.byted.org/simple/ -r requirements.lock
/opt/company/runtime-v1/bin/python -m pip check
```

If you then archive this modified directory with tar, deploy it at exactly the
same absolute path. It is not a newly relocatable conda-pack artifact. Arbitrary
relocation after private package installation needs another validated packing
stage. Avoid editable installs and dependencies on files outside the runtime.

## Reproducibility and licensing

The starter resolves the newest available packages within the selected Python
series. It records the resolved packages but is not bit-for-bit reproducible.
For production, review and commit an explicit Conda lock, pin Actions to reviewed
commit SHAs, and pin micromamba and the test container image digest.

packages.json contains package metadata and license identifiers, not a complete
license bundle or SBOM. Preserve bundled notices and collect required third-party
license texts/source offers before redistribution. Using conda-forge avoids
Anaconda defaults downloads; it does not waive individual package licenses.
