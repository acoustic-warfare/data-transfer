// File: data-transfer/demo/pyrdma.h
// Author: Irreq

#ifndef PYRDMA_H
#define PYRDMA_H

#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <rdma/rdma_cma.h>

// Define the tests
#define TEST_NON_ZERO(x) do { if ( (x)) die("error: " #x " failed (returned non-zero)." ); } while (0)
#define TEST_NULL(x) do { if (!(x)) die("error: " #x " failed (returned zero/null)."); } while (0)

// void die(const char *reason);

// void build_connection(struct rdma_cm_id *id);
// void build_params(struct rdma_conn_param *params);
// void destroy_connection(void *context);
// void * get_local_message_region(void *context);
// void on_connect(void *context);
// void send_mr(void *context);
// void set_mode(enum mode m);

#endif