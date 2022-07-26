CYC = cython
# ENV = data-transfer
ENV = gpu-rdma
CYFLAGS = --embed
PYTHON_VERSION = 3.7

CC = gcc
DEBUG = -Wall -Werror -v
CFLAGS = -O3 -march=native # $(DEBUG) 
CUDA_LIBS = -L/usr/local/cuda/lib64

PYMODULE = ~/miniconda3/envs/$(ENV)/include/python$(PYTHON_VERSION)m/
PYLIB = ~/miniconda3/envs/$(ENV)/lib
LIBS = -lm -lpython$(PYTHON_VERSION)m

RM = rm
BIN = run

OUT = build
SRC = src
LIB = lib

.PHONY: all

all: main fpga web_gauge
# all: main

main: lib
	$(CYC) $(CYFLAGS) -o $(OUT)/main.c src/main.pyx
	$(CC) $(CFLAGS) -I $(PYMODULE) -o $(BIN) $(OUT)/main.c -L $(PYLIB) $(LIBS)
fpga:
	$(CC) $(CFLAGS) -o fpga_emulator src/fpga_mic_em.c

test:
	$(CYC) $(CYFLAGS) -o $(OUT)/test.c src/transfer_real.pyx
	$(CC) $(CFLAGS) -I $(PYMODULE) -o test $(OUT)/test.c -L $(PYLIB) $(LIBS)


web_gauge:
	$(CYC) $(CYFLAGS) -o $(OUT)/web_live_gauge.c src/web_live_gauge.pyx
	$(CC) $(CFLAGS) -I $(PYMODULE) -o web_gauge $(OUT)/web_live_gauge.c -L $(PYLIB) $(LIBS)

# Cuda Cython Bridge
bridge.o:
	$(CC) $(CFLAGS) -I /usr/local/cuda/include -c -o $(OUT)/bridge.o $(SRC)/bridge.c -lstdc++

beam.o:
	nvcc --compiler-options '-fPIC' -c -o $(OUT)/beam.o $(SRC)/beam.cu

common.o:
	$(CC) $(CFLAGS) -c -o $(OUT)/common.o $(SRC)/common.c

cubridge.so: bridge.o beam.o common.o
	$(CC) $(CFLAGS) -shared -o $(LIB)/cubridge.so $(OUT)/bridge.o $(OUT)/beam.o $(OUT)/common.o $(CUDA_LIBS) -lcudart -lstdc++ -fPIC

lib: cubridge.so

.PHONY: clean
clean:
	$(RM) $(LIB)/*.so $(OUT)/*.o $(OUT)/main.c $(BIN) fpga_emulator web_gauge

