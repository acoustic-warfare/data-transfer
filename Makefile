CYC = cython
CYFLAGS = --embed
PYTHON_VERSION = 3.7

CC = gcc
CFLAGS = -Wall -Werror -Os

PYMODULE = ~/miniconda3/envs/gpu-rdma/include/python$(PYTHON_VERSION)m/
PYLIB = ~/miniconda3/envs/gpu-rdma/lib
LIBS = -lm -lpython$(PYTHON_VERSION)m

RM = rm
OUT = main.c
BIN = run

.PHONY: all

all: main

main:
	mkdir build
	$(CYC) $(CYFLAGS) -o build/$(OUT) src/main.pyx
	$(CC) $(CFALGS) -I $(PYMODULE) -o $(BIN) build/$(OUT) -L $(PYLIB) $(LIBS)

.PHONY: clean
clean:
	$(RM) build/$(OUT) $(BIN)
	rmdir build

