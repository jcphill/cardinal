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

# Cardinal's own build orchestration (Makefile/config/scripts) plus
# MOOSE: needed just to parse the Makefile at all, regardless of which
# target is requested -- config/check_deps.mk hard-errors on a missing
# MOOSE unconditionally, and build.mk/moose.mk (both under
# contrib/moose) are what resolve the compiler paths config/nekrs.mk
# and config/openmc.mk pass to cmake.
COPY Makefile ./
COPY config config
COPY scripts scripts
COPY contrib/moose contrib/moose

# NekRS in its own layer, built *before* OpenMC's submodules even exist
# in the image -- NekRS changes less often than OpenMC, so this way an
# OpenMC-only commit never invalidates NekRS's (already expensive)
# build. ENABLE_OPENMC=no only for this one invocation: without it,
# check_deps.mk's OpenMC-availability check would hard-error here even
# though we're only asking for build_nekrs, since contrib/openmc and
# contrib/nuclear_data aren't copied in yet.
COPY contrib/nekRS contrib/nekRS
RUN make ENABLE_OPENMC=no build_nekrs

# OpenMC in its own layer. nuclear_data is required here too --
# check_deps.mk hard-errors without it whenever ENABLE_OPENMC=yes (the
# default, so no override needed this time; NekRS is already copied in
# from the layer above, so its own availability check still passes).
COPY contrib/openmc contrib/openmc
COPY contrib/nuclear_data contrib/nuclear_data
RUN make build_openmc

# Now bring in the rest of Cardinal's own source (changes on every
# commit) and do the real build. NekRS/OpenMC are already built and
# installed from the layers above; re-running `make`'s own
# build_nekrs/build_openmc order-only prerequisites here is cheap --
# they just re-check the already-built, nested CMake build trees for
# "nothing to do" rather than rebuilding them.
COPY . .

RUN make -j$(nproc)
