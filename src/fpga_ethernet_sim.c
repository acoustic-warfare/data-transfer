/* fpga_ethernet_sim.c
// File: data-transfer/demo/pyrdma.c
// Author: Irreq

Create a fake data transfer packet from FPGA for Data Transfer

gcc -o run fpga_ethernet_sim.c

*/

#include <sys/socket.h>
#include <arpa/inet.h> //inet_addr
#include <unistd.h>    //write
#include <time.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TCP_PORT 45405
#define TCP_ADDRESS "localhost"

#pragma pack(1)

// Version 1.0
typedef struct payload_protocol_t {
    int id;
    int protocol_version;
    int fs;
    int fs_nr;
    int samples;  // Every mic
    int sample_error;  // If error inside
    int bitstream[192];
} payload_protocol;

#pragma pack()


int msleep(unsigned int tms)
{
    return usleep(tms * 1000);
}

void transmitMicArraydata(int sock, void *ctx, uint32_t ctxsize) {
    if (write(sock, ctx, ctxsize) < 0) {
        printf("Error sending message.");
        close(sock);
        exit(1);
    }
    return;
}

int main() {
    const int PORT = TCP_PORT;
    const char *ADDRESS = TCP_ADDRESS;
    int BUFFSIZE = sizeof(payload_protocol);
    char buff[BUFFSIZE];
    int sock;
    int nread;
    time_t t;

    srand((unsigned)time(&t));

    struct sockaddr_in server_address;
    memset(&server_address, 0, sizeof(server_address));
    server_address.sin_family = AF_INET;
    inet_pton(AF_INET, ADDRESS, &server_address.sin_addr);
    server_address.sin_port = htons(PORT);

    if ((sock = socket(PF_INET, SOCK_STREAM, 0)) < 0)
    {
        printf("ERROR: Socket creation failed\n");
        return 1;
    }

    if (connect(sock, (struct sockaddr *)&server_address, sizeof(server_address)) < 0)
    {
        printf("ERROR: Unable to connect to server\n");
        return 1;
    }

    printf("Connected to %s\n", ADDRESS);

    payload_protocol data;

    // Send data a billion times
    for (int i = 0; i < 1e9; i++) {
        data.id = i;
        data.protocol_version = 1;
        data.fs = 16000;
        data.fs_nr = i;
        data.samples = 64;
        data.sample_error = 0;

        // Fill array of dummy data
        memset(data.bitstream, 0, sizeof data.bitstream);

        // Sending dummy data
        transmitMicArraydata(sock, &data, sizeof(payload_protocol));
        usleep(1e6 / data.fs);
    }

    close(sock);
    return 0;
}