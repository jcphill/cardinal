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

# Build the heavy, infrequently-changing native dependencies (NekRS,
# OpenMC) in their own layer, from just Cardinal's build orchestration
# (Makefile/config/scripts) plus the public submodules they actually
# need -- config/{nekrs,openmc}.mk's build_nekrs/build_openmc targets
# only depend on these (confirmed directly: config/check_deps.mk's
# existence checks never touch src/, include/, or test/), not on
# anything that changes on every commit. nuclear_data is required too
# -- check_deps.mk hard-errors without it whenever ENABLE_OPENMC=yes.
# As long as none of these inputs change, this whole layer -- and the
# NekRS/OpenMC build it runs -- is skipped entirely by Docker's cache,
# even when Cardinal's own source below does.
COPY Makefile ./
COPY config config
COPY scripts scripts
COPY contrib/moose contrib/moose
COPY contrib/nekRS contrib/nekRS
COPY contrib/openmc contrib/openmc
COPY contrib/nuclear_data contrib/nuclear_data

RUN make build_nekrs build_openmc

# Now bring in the rest of Cardinal's own source (changes on every
# commit) and do the real build. NekRS/OpenMC are already built and
# installed from the layer above; re-running `make`'s own
# build_nekrs/build_openmc order-only prerequisites here is cheap --
# they just re-check the already-built, nested CMake build trees for
# "nothing to do" rather than rebuilding them.
COPY . .

RUN make -j$(nproc)
