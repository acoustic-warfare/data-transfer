#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from dask_cuda import LocalCUDACluster
from distributed import Client
 
cluster = LocalCUDACluster(protocol="tcp")
client = Client(cluster)