# Built from a CI checkout that has already run scripts/get-dependencies.sh
# (see .github/workflows/docker-build.yml) -- submodules are part of the
# build context via COPY below, not fetched inside the image. This matters
# for caching: a `git clone` baked into a RUN step is cached by its literal
# command text, not by what it actually fetches, so Docker would happily
# reuse the very first clone forever and never pick up new commits. COPY is
# content-hashed, so this layer (and everything after it) correctly
# invalidates only when the checked-out source actually changes.
FROM idaholab/moose-dev:latest

ENV HDF5_ROOT=/opt/petsc
ENV BASH_ENV=/environment

SHELL ["/bin/bash", "-c"]

ENV NEKRS_HOME=/cardinal/install

WORKDIR /cardinal

COPY . .

RUN make -j$(nproc)
