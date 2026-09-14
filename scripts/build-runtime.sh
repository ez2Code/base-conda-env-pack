#!/usr/bin/env bash
set -euo pipefail

: "${PYTHON_VERSION:=3.11}"
: "${CONDA_OVERRIDE_GLIBC:=2.24}"
export CONDA_OVERRIDE_GLIBC
[[ "$(uname -s)" == Linux ]] || {
  echo 'This starter builds only on Linux.' >&2
  exit 1
}
host_arch=$(uname -m)
: "${TARGET_ARCH:=$host_arch}"
case "$TARGET_ARCH" in
  x86_64)
    conda_platform=linux-64
    docker_platform=linux/amd64
    expected_machine=x86_64
    ;;
  arm64|aarch64)
    TARGET_ARCH=arm64
    conda_platform=linux-aarch64
    docker_platform=linux/arm64
    expected_machine=aarch64
    ;;
  *) echo "Unsupported architecture: $TARGET_ARCH" >&2; exit 1 ;;
esac
[[ "$host_arch" == "$expected_machine" ]] || {
  echo "Native build required: target=$TARGET_ARCH, host=$host_arch" >&2
  exit 1
}
# Prevent an inherited Conda platform override from selecting foreign binaries.
export CONDA_SUBDIR="$conda_platform"
case "$PYTHON_VERSION" in
  3.11|3.12|3.13|3.14) ;;
  *) echo 'Unsupported Python series' >&2; exit 1 ;;
esac

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
runtime="$build_dir/runtime"
pack_tools="$build_dir/pack-tools"
dist_dir="$PWD/dist"
mkdir -p "$dist_dir"
channel=https://conda.anaconda.org/conda-forge

micromamba create -y -p "$runtime" --override-channels \
  --strict-channel-priority -c "$channel" "python=$PYTHON_VERSION" pip
micromamba create -y -p "$pack_tools" --override-channels \
  --strict-channel-priority -c "$channel" \
  python=3.11 conda-pack=0.8.1 setuptools=80.9.0

# conda-pack 0.8.1 imports pkg_resources, removed in setuptools 82.
"$pack_tools/bin/python" -c 'import pkg_resources; import conda_pack.cli'
"$pack_tools/bin/conda-pack" --version
"$pack_tools/bin/python" -m pip check

# Check installed origins, not only the requested channel configuration.
"$pack_tools/bin/python" - "$runtime" "$dist_dir" "$conda_platform" <<'PY'
import json
import pathlib
import sys
from urllib.parse import urlparse

prefix, output = map(pathlib.Path, sys.argv[1:3])
expected_subdir = sys.argv[3]
records = [json.loads(p.read_text()) for p in sorted((prefix / 'conda-meta').glob('*.json'))]
for record in records:
    url = urlparse(record.get('url', ''))
    if url.hostname != 'conda.anaconda.org' or not url.path.startswith('/conda-forge/'):
        raise SystemExit('Unexpected package origin: ' + record.get('url', '<missing>'))
    if record.get('subdir') not in (expected_subdir, 'noarch'):
        raise SystemExit('Unexpected package architecture: ' + record['name'])
(output / 'packages.json').write_text(json.dumps(records, indent=2) + '\n')
PY

micromamba list -p "$runtime" --explicit > "$dist_dir/conda-explicit.txt"
"$runtime/bin/python" -m pip check
"$runtime/bin/python" -m pip freeze --all > "$dist_dir/pip-freeze.txt"
"$runtime/bin/python" -VV > "$dist_dir/python-version.txt"
micromamba --version > "$dist_dir/micromamba-version.txt"
archive="python-${PYTHON_VERSION}-linux-${TARGET_ARCH}.tar.gz"
"$pack_tools/bin/conda-pack" -p "$runtime" -o "$dist_dir/$archive"

# Test without access to the original prefix, host libraries, or network.
# Stretch exercises the glibc 2.24 floor; Buster checks Debian 10 as well.
for test_case in debian:stretch-slim,2.24 debian:buster-slim,2.28; do
  test_image=${test_case%,*}
  expected_glibc=${test_case#*,}
  docker run --rm --network none --platform "$docker_platform" \
  -v "$dist_dir:/artifacts:ro" "$test_image" \
  bash -euc '
    actual_glibc=$(getconf GNU_LIBC_VERSION)
    echo "Testing $actual_glibc"
    test "$actual_glibc" = "glibc $2"
    test "$(uname -m)" = "$3"
    mkdir -p /opt/relocated-runtime
    tar -xzf "/artifacts/$1" -C /opt/relocated-runtime
    /opt/relocated-runtime/bin/python /opt/relocated-runtime/bin/conda-unpack
    /opt/relocated-runtime/bin/python -I -c "import platform, sys; assert platform.machine() == sys.argv[1], platform.machine()" "$3"
    /opt/relocated-runtime/bin/python -I -c "import ssl, sqlite3, ctypes, bz2, lzma, zlib; print(ssl.OPENSSL_VERSION)"
    /opt/relocated-runtime/bin/python -m pip --version
    # Relocated entry points may use /usr/bin/env python3.X.
    export PATH="/opt/relocated-runtime/bin:$PATH"
    /opt/relocated-runtime/bin/pip --version
    /opt/relocated-runtime/bin/python -m pip check
  ' bash "$archive" "$expected_glibc" "$expected_machine"
done

(
  cd "$dist_dir"
  sha256sum "$archive" packages.json conda-explicit.txt pip-freeze.txt \
    python-version.txt micromamba-version.txt > SHA256SUMS
)
