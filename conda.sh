#!/usr/bin/env sh

# Require libnuma-dev

conda create -n ucx -c conda-forge -c rapidsai \
  cudatoolkit=11.7 ucx-proc=*=gpu ucx ucx-py python=3.8

../contrib/configure-release \
--enable-mt \
--prefix="$CONDA_PREFIX" \
--with-cuda="$CUDA_HOME" \
--enable-mt \
--with-rdmacm \
--with-verbs \
CPPFLAGS="-I$CUDA_HOME/include"