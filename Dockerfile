# COPY, not a baked-in git clone: Docker caches a RUN step by its command
# text, not what it fetches, so a clone would never see new commits.
FROM idaholab/moose-dev:latest

ENV HDF5_ROOT=/opt/petsc
ENV BASH_ENV=/environment

SHELL ["/bin/bash", "-c"]

ENV NEKRS_HOME=/cardinal/install

WORKDIR /cardinal

# Tiny (~49KB) and rarely changes.
COPY contrib/nuclear_data contrib/nuclear_data

# Only the MOOSE files needed to parse the Makefile (compiler paths for
# nekrs.mk/openmc.mk, mandatory includes, and the HIT-parser check) --
# not MOOSE's much larger, much more frequently changing source tree.
COPY Makefile ./
COPY config config
COPY scripts scripts
COPY contrib/moose/framework/build.mk contrib/moose/framework/build.mk
COPY contrib/moose/framework/moose.mk contrib/moose/framework/moose.mk
COPY contrib/moose/framework/app.mk contrib/moose/framework/app.mk
COPY contrib/moose/framework/contrib/neml2.mk contrib/moose/framework/contrib/neml2.mk
COPY contrib/moose/framework/contrib/hit contrib/moose/framework/contrib/hit
COPY contrib/moose/modules/modules.mk contrib/moose/modules/modules.mk

# NekRS changes less often than OpenMC, so build it first. The
# placeholder satisfies check_deps.mk's OpenMC-availability check;
# removed before the real submodule is copied in below.
COPY contrib/nekRS contrib/nekRS
RUN mkdir -p contrib/openmc && touch contrib/openmc/DOCKERFILE_PLACEHOLDER && make build_nekrs

RUN rm -f contrib/openmc/DOCKERFILE_PLACEHOLDER
COPY contrib/openmc contrib/openmc
RUN make build_openmc

# NekRS/OpenMC are already built; re-running their order-only
# prerequisites here is cheap.
COPY . .

RUN make -j$(nproc)
