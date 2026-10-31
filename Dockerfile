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

# Cardinal's own build orchestration (Makefile/config/scripts) plus the
# specific MOOSE files needed just to *parse* the Makefile, regardless
# of which target is requested -- verified directly with a `make -n`
# dry run against a partial checkout, not just by reading the Makefiles:
# build.mk/moose.mk/app.mk resolve the compiler paths config/nekrs.mk
# and config/openmc.mk pass to cmake, modules/modules.mk is included
# unconditionally, moose.mk itself mandatorily includes contrib/neml2.mk,
# and moose.mk separately hard-errors unless framework/contrib/hit (the
# HIT input-file parser) is non-empty -- that whole tiny (~1MB)
# directory is copied rather than picking one file out of it, since
# nothing here actually needs to *build* it, just see that it exists.
# The rest of MOOSE's famously large tree (framework/src, modules/*,
# everything else) isn't needed at all until the final build below.
COPY Makefile ./
COPY config config
COPY scripts scripts
COPY contrib/moose/framework/build.mk contrib/moose/framework/build.mk
COPY contrib/moose/framework/moose.mk contrib/moose/framework/moose.mk
COPY contrib/moose/framework/app.mk contrib/moose/framework/app.mk
COPY contrib/moose/framework/contrib/neml2.mk contrib/moose/framework/contrib/neml2.mk
COPY contrib/moose/framework/contrib/hit contrib/moose/framework/contrib/hit
COPY contrib/moose/modules/modules.mk contrib/moose/modules/modules.mk

# nuclear_data for real, not a placeholder -- it's tiny (~49KB) and
# changes about as rarely as anything in this Dockerfile, so there's no
# benefit to deferring it the way OpenMC's actual (large, slow-to-build)
# submodule is deferred below.
COPY contrib/nuclear_data contrib/nuclear_data

# NekRS in its own layer, built *before* OpenMC's real submodule exists
# in the image -- NekRS changes less often than OpenMC, so this way an
# OpenMC-only commit never invalidates NekRS's (already expensive)
# build. ENABLE_OPENMC defaults to yes, so check_deps.mk's OpenMC-
# availability check would otherwise hard-error here even though we're
# only asking for build_nekrs. Rather than override ENABLE_OPENMC=no
# for just this one invocation -- a divergent flag path from the real
# build, which could silently start mattering to NekRS's own build if a
# future Cardinal change ever makes it care about ENABLE_OPENMC --
# satisfy that check with a placeholder file we create and own
# ourselves, deleted before the real submodule is copied in below. The
# check is a plain, non-dotfile-sensitive `ls` test (confirmed via a
# real `make -n` dry run -- a leading-dot filename is invisible to it),
# so any non-empty, non-dotfile placeholder works.
COPY contrib/nekRS contrib/nekRS
RUN mkdir -p contrib/openmc && touch contrib/openmc/DOCKERFILE_PLACEHOLDER && make build_nekrs

# OpenMC in its own layer. Remove the placeholder above before copying
# in the real submodule -- NekRS and nuclear_data are already present
# from the layers above, so their own availability checks still pass.
RUN rm -f contrib/openmc/DOCKERFILE_PLACEHOLDER
COPY contrib/openmc contrib/openmc
RUN make build_openmc

# Now bring in the rest of Cardinal's own source (changes on every
# commit) and do the real build. NekRS/OpenMC are already built and
# installed from the layers above; re-running `make`'s own
# build_nekrs/build_openmc order-only prerequisites here is cheap --
# they just re-check the already-built, nested CMake build trees for
# "nothing to do" rather than rebuilding them.
COPY . .

RUN make -j$(nproc)
