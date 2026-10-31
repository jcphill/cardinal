FROM idaholab/moose-dev:latest

ENV HDF5_ROOT=/opt/petsc
ENV BASH_ENV=/environment

SHELL ["/bin/bash", "-c"]

ENV NEKRS_HOME=/cardinal/install

WORKDIR /cardinal

# Tiny (~49KB) and rarely changes.
COPY contrib/nuclear_data contrib/nuclear_data

# Only the config/*.mk and MOOSE files actually needed to parse the
# Makefile, not their much larger, more frequently changing trees.
COPY Makefile ./
COPY config/check_deps.mk config/check_deps.mk
COPY config/check_modules.mk config/check_modules.mk
COPY config/check_nekrs.mk config/check_nekrs.mk
COPY config/add_flags.mk config/add_flags.mk
COPY contrib/moose/framework/build.mk contrib/moose/framework/build.mk
COPY contrib/moose/framework/moose.mk contrib/moose/framework/moose.mk
COPY contrib/moose/framework/app.mk contrib/moose/framework/app.mk
COPY contrib/moose/framework/contrib/neml2.mk contrib/moose/framework/contrib/neml2.mk
COPY contrib/moose/modules/modules.mk contrib/moose/modules/modules.mk

# NekRS changes less often than OpenMC, so build it first. openmc.mk,
# contrib/openmc, and the HIT parser are only existence-checked here,
# not needed for real until later.
COPY config/nekrs.mk config/nekrs.mk
COPY contrib/nekRS contrib/nekRS
# Cardinal's own CFLAGS/LDFLAGS (incl. "-include .../MooseConfig.h")
# leak into third-party sub-builds like HYPRE's; MooseConfig.h is
# normally generated as a side effect of building $(app_EXEC), which
# this layer never asks for. A placeholder satisfies the compile check;
# removed before the final build so it regenerates for real.
RUN mkdir -p contrib/openmc contrib/moose/framework/contrib/hit \
             contrib/moose/framework/include/base && \
    touch contrib/openmc/DOCKERFILE_PLACEHOLDER \
          contrib/moose/framework/contrib/hit/DOCKERFILE_PLACEHOLDER \
          contrib/moose/framework/include/base/MooseConfig.h \
          config/openmc.mk && \
    make build_nekrs || \
      (cat build/nekrs/HYPRE_BUILD-prefix/src/HYPRE_BUILD/src/config.log; exit 1)

RUN rm -f contrib/openmc/DOCKERFILE_PLACEHOLDER
COPY config/openmc.mk config/openmc.mk
COPY contrib/openmc contrib/openmc
RUN make build_openmc

# Remove the MooseConfig.h placeholder so the real build regenerates it
# -- otherwise its build-time mtime (newer than anything COPY'd from
# the checkout) could fool Make into thinking it's already up to date.
RUN rm -f contrib/moose/framework/include/base/MooseConfig.h \
           contrib/moose/framework/contrib/hit/DOCKERFILE_PLACEHOLDER

# COPY preserves checkout-time mtimes, which across separate CI runs
# are always newer than yesterday's cached build output -- Make (and
# nested CMake sub-builds like NekRS's bundled ADIOS2) would otherwise
# reconfigure and rebuild from scratch here. Touching everything avoids
# chasing each nested sub-build's own staleness comparison individually.
COPY . .
RUN find . -exec touch {} +

RUN make -j$(nproc)
