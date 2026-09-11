# Portable Python starter

Copy this directory's contents, including `.github`, to a GitHub repository.
Run **Actions > Build portable Python > Run workflow** and select Python.
Download the completed run's artifact. No release is published automatically.
Artifacts expire after 30 days and downloading them can require GitHub login.
For durable distribution, publish the reviewed output to your artifact store or
GitHub Release separately.

The workflow creates Linux x86_64 Python + pip using only conda-forge, with
conda-pack in a separate build environment. It checks installed package origins,
exports exact Conda package URLs, and tests relocation in Debian 10 without
network access. No internal packages or repository credentials are needed.

The glibc solver baseline is 2.28 and the minimum supported distribution is
Debian 10. The container test asserts the actual libc version.
Debian 9 / glibc 2.24 is outside this template's compatibility target.
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

Run from the extracted GitHub artifact directory. Use a new empty destination:

```bash
sha256sum -c SHA256SUMS
mkdir -p /opt/company/runtime-v1
tar -xzf python-3.11-linux-x86_64.tar.gz -C /opt/company/runtime-v1
/opt/company/runtime-v1/bin/python /opt/company/runtime-v1/bin/conda-unpack
/opt/company/runtime-v1/bin/python -V
```

Adjust the archive name for the selected Python series. After conda-unpack,
do not move this directory. Extract the original archive again for another path.

Install private dependencies in the isolated build environment:

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
