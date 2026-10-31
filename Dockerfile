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
RUN mkdir -p contrib/openmc contrib/moose/framework/contrib/hit && \
    touch contrib/openmc/DOCKERFILE_PLACEHOLDER \
          contrib/moose/framework/contrib/hit/DOCKERFILE_PLACEHOLDER \
          config/openmc.mk && \
    make build_nekrs

RUN rm -f contrib/openmc/DOCKERFILE_PLACEHOLDER \
           contrib/moose/framework/contrib/hit/DOCKERFILE_PLACEHOLDER
COPY config/openmc.mk config/openmc.mk
COPY contrib/openmc contrib/openmc
RUN make build_openmc

# NekRS/OpenMC are already built; re-running their order-only
# prerequisites here is cheap.
COPY . .

RUN make -j$(nproc)
