#!/bin/bash -e

JULIA_PATH=$1
JULIA_VERSION=$2

mkdir -p "$JULIA_PATH"
if [[ $JULIA_VERSION = nightly ]]; then
    julia_url=https://s3.amazonaws.com/julianightlies/bin/linux/x64/julia-latest-linux64.tar.gz
    has_sig=0
elif [[ $JULIA_VERSION =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
    julia_url=https://s3.amazonaws.com/julialang/bin/linux/x64/${BASH_REMATCH[1]}/julia-${BASH_REMATCH[0]}-linux-x86_64.tar.gz
    has_sig=1
elif [[ $JULIA_VERSION =~ ^([0-9]+\.[0-9]+)$ ]]; then
    julia_url=https://s3.amazonaws.com/julialang/bin/linux/x64/${BASH_REMATCH[1]}/julia-${BASH_REMATCH[1]}-latest-linux-x86_64.tar.gz
    has_sig=0
fi
echo "Downloading julia $JULIA_VERSION from $julia_url"
curl -sSL "$julia_url" -o julia.tar.gz
if ((has_sig)); then
    curl -sSL "$julia_url.asc" -o julia.tar.gz.asc
    export GNUPGHOME="$(mktemp -d)"
    # http://julialang.org/juliareleases.asc
    # Julia (Binary signing key) <buildbot@julialang.org>
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 3673DF529D9049477F76B37566E3C7DC03D6E495
    gpg --batch --verify julia.tar.gz.asc julia.tar.gz
    rm -r "$GNUPGHOME" julia.tar.gz.asc
fi
tar -xzf julia.tar.gz -C $JULIA_PATH --strip-components 1
shopt -s nullglob
for f in "$JULIA_PATH/lib/julia/libcrypto"* "$JULIA_PATH/lib/julia/libssl"* \
         "$JULIA_PATH/lib/julia/libmbed"* "$JULIA_PATH/lib/julia/libgit2"*; do
    rm "$f"
done
rm -rf julia.tar.gz*
