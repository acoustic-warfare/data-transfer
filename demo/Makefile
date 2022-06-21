.PHONY: clean

CFLAGS  := -Wall -Werror -g
LD      := gcc
LDLIBS  := ${LDLIBS} -lrdmacm -libverbs -lpthread -fPIC

APPS    := pyrdma.so

# gcc -shared -Wl,-soname,rdma-common -o rdma-common.so -fPIC rdma-common.c

all: ${APPS}

pyrdma.so: pyrdma.o
	${LD} -shared -Wl,-soname,pyrdma -o $@ $^ ${LDLIBS}


clean:
	rm -f *.so ${APPS}
	rm -f *.o ${APPS}