FROM base/devel

RUN pacman --noconfirm -Sy systemd git lsb-release cmake mbedtls http-parser suitesparse fftw gmp mpfr libgit2

RUN useradd -U -G wheel -m julia

ENV JULIA_PATH /usr/local/julia
ARG JULIA_VERSION=nightly

ADD download_julia.sh /download_julia.sh

RUN bash -e /download_julia.sh "$JULIA_PATH" "$JULIA_VERSION"

ENV PATH $JULIA_PATH/bin:$PATH

CMD ["julia"]
