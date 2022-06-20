#!/usr/bin/env sh

######################################################################
# @author      : Irreq (irreq@protonmail.com)
# @file        : remfs
# @created     : monday jun 20, 2022 11:28:43 CEST
#
# @description : Startup script for nodes
######################################################################

# Enable GPUDirect RDMA if not started already
sudo service nv_peer_mem restart