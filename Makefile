CYC = cython
# ENV = data-transfer
ENV = gpu-rdma
CYFLAGS = --embed
PYTHON_VERSION = 3.7

CC = gcc
CFLAGS = -v -Wall -Werror -Os

PYMODULE = ~/miniconda3/envs/$(ENV)/include/python$(PYTHON_VERSION)m/
PYLIB = ~/miniconda3/envs/$(ENV)/lib
LIBS = -lm -lpython$(PYTHON_VERSION)m

RM = rm
OUT = main.c
BIN = run

.PHONY: all

all: main fpga

main:
	$(CYC) $(CYFLAGS) -o build/$(OUT) src/main.pyx
	$(CC) $(CFLAGS) -I $(PYMODULE) -o $(BIN) build/$(OUT) -L $(PYLIB) $(LIBS)
fpga:
	$(CC) $(CFLAGS) -o fpga_emulator src/fpga_mic_em.c

.PHONY: clean
clean:
	$(RM) build/$(OUT) $(BIN) fpga_emulator

