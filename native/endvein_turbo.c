#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <errno.h>

#if defined(__APPLE__) || defined(__FreeBSD__)
#define USE_KQUEUE 1
#include <sys/event.h>
#include <sys/time.h>
#else
#define USE_EPOLL 1
#include <sys/epoll.h>
#endif

#define MAX_EVENTS 512
#define BUFFER_SIZE 8192

typedef void (*endvein_request_cb)(
    int client_fd,
    int method,
    const char* path,
    int path_len,
    const char* body,
    int body_len,
    int keep_alive
);

static const char HTTP_JSON_200_HDR[] =
    "HTTP/1.1 200 OK\r\n"
    "Server: Endvein-Turbo\r\n"
    "Content-Type: application/json; charset=utf-8\r\n"
    "Content-Length: ";
static const int HTTP_JSON_200_HDR_LEN = sizeof(HTTP_JSON_200_HDR) - 1;

static const char HTTP_TEXT_200_HDR[] =
    "HTTP/1.1 200 OK\r\n"
    "Server: Endvein-Turbo\r\n"
    "Content-Type: text/plain; charset=utf-8\r\n"
    "Content-Length: ";
static const int HTTP_TEXT_200_HDR_LEN = sizeof(HTTP_TEXT_200_HDR) - 1;

static const char CONN_KEEP_ALIVE[] = "\r\nConnection: keep-alive\r\n\r\n";
static const int CONN_KEEP_ALIVE_LEN = sizeof(CONN_KEEP_ALIVE) - 1;

static const char CONN_CLOSE[] = "\r\nConnection: close\r\n\r\n";
static const int CONN_CLOSE_LEN = sizeof(CONN_CLOSE) - 1;

// Pre-computed length strings for lengths 0..1023
static char LENGTH_CACHE[1024][8];
static int LENGTH_CACHE_LEN[1024];

__attribute__((constructor))
static void init_length_cache(void) {
    for (int i = 0; i < 1024; i++) {
        LENGTH_CACHE_LEN[i] = snprintf(LENGTH_CACHE[i], 8, "%d", i);
    }
}

static inline int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

// Create, configure, and bind a listening server socket with SO_REUSEPORT
int endvein_turbo_listen(const char* host, int port, int backlog) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) return -1;

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((uint16_t)port);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(server_fd);
        return -2;
    }

    if (listen(server_fd, backlog > 0 ? backlog : 4096) < 0) {
        close(server_fd);
        return -3;
    }

    set_nonblocking(server_fd);
    return server_fd;
}

// Initialize kqueue / epoll instance for this worker
int endvein_turbo_create_poller(int server_fd) {
#if USE_KQUEUE
    int kq = kqueue();
    if (kq < 0) return -1;

    struct kevent change;
    EV_SET(&change, server_fd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
    if (kevent(kq, &change, 1, NULL, 0, NULL) < 0) {
        close(kq);
        return -2;
    }
    return kq;
#elif USE_EPOLL
    int epfd = epoll_create1(0);
    if (epfd < 0) return -1;

    struct epoll_event ev;
    ev.events = EPOLLIN | EPOLLET;
    ev.data.fd = server_fd;
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, server_fd, &ev) < 0) {
        close(epfd);
        return -2;
    }
    return epfd;
#endif
}

// High-speed scatter-gather zero-copy JSON response sender
int endvein_turbo_send_json(int client_fd, const char* body, int body_len, int keep_alive) {
    char len_str[16];
    const char* len_ptr;
    int len_str_len;

    if (body_len >= 0 && body_len < 1024) {
        len_ptr = LENGTH_CACHE[body_len];
        len_str_len = LENGTH_CACHE_LEN[body_len];
    } else {
        len_str_len = snprintf(len_str, sizeof(len_str), "%d", body_len);
        len_ptr = len_str;
    }

    struct iovec iov[4];
    iov[0].iov_base = (void*)HTTP_JSON_200_HDR;
    iov[0].iov_len = HTTP_JSON_200_HDR_LEN;
    iov[1].iov_base = (void*)len_ptr;
    iov[1].iov_len = len_str_len;
    iov[2].iov_base = (void*)(keep_alive ? CONN_KEEP_ALIVE : CONN_CLOSE);
    iov[2].iov_len = keep_alive ? CONN_KEEP_ALIVE_LEN : CONN_CLOSE_LEN;
    iov[3].iov_base = (void*)body;
    iov[3].iov_len = body_len;

    ssize_t written = writev(client_fd, iov, 4);
    if (!keep_alive) {
        close(client_fd);
    }
    return (int)written;
}

// High-speed scatter-gather zero-copy Text response sender
int endvein_turbo_send_text(int client_fd, const char* body, int body_len, int keep_alive) {
    char len_str[16];
    const char* len_ptr;
    int len_str_len;

    if (body_len >= 0 && body_len < 1024) {
        len_ptr = LENGTH_CACHE[body_len];
        len_str_len = LENGTH_CACHE_LEN[body_len];
    } else {
        len_str_len = snprintf(len_str, sizeof(len_str), "%d", body_len);
        len_ptr = len_str;
    }

    struct iovec iov[4];
    iov[0].iov_base = (void*)HTTP_TEXT_200_HDR;
    iov[0].iov_len = HTTP_TEXT_200_HDR_LEN;
    iov[1].iov_base = (void*)len_ptr;
    iov[1].iov_len = len_str_len;
    iov[2].iov_base = (void*)(keep_alive ? CONN_KEEP_ALIVE : CONN_CLOSE);
    iov[2].iov_len = keep_alive ? CONN_KEEP_ALIVE_LEN : CONN_CLOSE_LEN;
    iov[3].iov_base = (void*)body;
    iov[3].iov_len = body_len;

    ssize_t written = writev(client_fd, iov, 4);
    if (!keep_alive) {
        close(client_fd);
    }
    return (int)written;
}

// Generic response sender
int endvein_turbo_send(int client_fd, const char* data, int len, int keep_alive) {
    ssize_t total_sent = 0;
    while (total_sent < len) {
        ssize_t sent = send(client_fd, data + total_sent, len - total_sent, 0);
        if (sent < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            close(client_fd);
            return -1;
        }
        total_sent += sent;
    }

    if (!keep_alive) {
        close(client_fd);
    }
    return (int)total_sent;
}

// Close client socket
void endvein_turbo_close(int client_fd) {
    close(client_fd);
}

// Fast HTTP request parser
static inline void parse_and_dispatch(int client_fd, char* buf, int bytes_read, endvein_request_cb cb) {
    if (bytes_read < 14) return; // Minimum valid HTTP request: "GET / HTTP/1.1\r\n"

    int method = 0; // 0=GET, 1=POST, 2=PUT, 3=DELETE, 4=PATCH, 5=HEAD, 6=OPTIONS
    int path_start = 4;

    if (buf[0] == 'G' && buf[1] == 'E' && buf[2] == 'T' && buf[3] == ' ') {
        method = 0;
        path_start = 4;
    } else if (buf[0] == 'P' && buf[1] == 'O' && buf[2] == 'S' && buf[3] == 'T' && buf[4] == ' ') {
        method = 1;
        path_start = 5;
    } else if (buf[0] == 'P' && buf[1] == 'U' && buf[2] == 'T' && buf[3] == ' ') {
        method = 2;
        path_start = 4;
    } else if (buf[0] == 'D' && buf[1] == 'E' && buf[2] == 'L' && buf[3] == 'E' && buf[4] == 'T' && buf[5] == 'E' && buf[6] == ' ') {
        method = 3;
        path_start = 7;
    } else if (buf[0] == 'P' && buf[1] == 'A' && buf[2] == 'T' && buf[3] == 'C' && buf[4] == 'H' && buf[5] == ' ') {
        method = 4;
        path_start = 6;
    } else if (buf[0] == 'H' && buf[1] == 'E' && buf[2] == 'A' && buf[3] == 'D' && buf[4] == ' ') {
        method = 5;
        path_start = 5;
    } else if (buf[0] == 'O' && buf[1] == 'P' && buf[2] == 'T' && buf[3] == 'I' && buf[4] == 'O' && buf[5] == 'N' && buf[6] == 'S' && buf[7] == ' ') {
        method = 6;
        path_start = 8;
    }

    // Find end of path
    int path_end = path_start;
    while (path_end < bytes_read && buf[path_end] != ' ' && buf[path_end] != '?') {
        path_end++;
    }
    int path_len = path_end - path_start;

    // Fast check for keep-alive: default is 1 for HTTP/1.1 unless "close" is present
    int keep_alive = 1;
    char* close_ptr = strstr(buf, "close");
    if (close_ptr != NULL && (close_ptr - buf) < bytes_read) {
        keep_alive = 0;
    }

    // Check for body after \r\n\r\n
    const char* body = NULL;
    int body_len = 0;
    char* header_end = strstr(buf, "\r\n\r\n");
    if (header_end != NULL) {
        int body_offset = (int)(header_end - buf) + 4;
        if (body_offset < bytes_read) {
            body = buf + body_offset;
            body_len = bytes_read - body_offset;
        }
    }

    // Invoke Dart callback
    cb(client_fd, method, buf + path_start, path_len, body, body_len, keep_alive);
}

// Poll ready events and dispatch them directly to Dart
int endvein_turbo_poll(int server_fd, int poller_fd, int timeout_ms, endvein_request_cb cb) {
    char buf[BUFFER_SIZE];
    int processed_events = 0;

#if USE_KQUEUE
    struct timespec ts;
    ts.tv_sec = timeout_ms / 1000;
    ts.tv_nsec = (timeout_ms % 1000) * 1000000;

    struct kevent events[MAX_EVENTS];
    int nev = kevent(poller_fd, NULL, 0, events, MAX_EVENTS, timeout_ms >= 0 ? &ts : NULL);

    for (int i = 0; i < nev; i++) {
        int fd = (int)events[i].ident;

        if (fd == server_fd) {
            while (1) {
                struct sockaddr_in client_addr;
                socklen_t client_len = sizeof(client_addr);
                int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
                if (client_fd < 0) break;

                int nodelay = 1;
                setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));
                set_nonblocking(client_fd);

                struct kevent client_change;
                EV_SET(&client_change, client_fd, EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
                kevent(poller_fd, &client_change, 1, NULL, 0, NULL);
            }
        } else {
            if (events[i].flags & (EV_EOF | EV_ERROR)) {
                close(fd);
                continue;
            }

            while (1) {
                ssize_t bytes_read = read(fd, buf, sizeof(buf) - 1);
                if (bytes_read > 0) {
                    buf[bytes_read] = '\0';
                    parse_and_dispatch(fd, buf, (int)bytes_read, cb);
                    processed_events++;
                } else {
                    if (bytes_read < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                        break;
                    }
                    close(fd);
                    break;
                }
            }
        }
    }
#elif USE_EPOLL
    struct epoll_event events[MAX_EVENTS];
    int nev = epoll_wait(poller_fd, events, MAX_EVENTS, timeout_ms);

    for (int i = 0; i < nev; i++) {
        int fd = events[i].data.fd;

        if (fd == server_fd) {
            while (1) {
                struct sockaddr_in client_addr;
                socklen_t client_len = sizeof(client_addr);
                int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
                if (client_fd < 0) break;

                int nodelay = 1;
                setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));
                set_nonblocking(client_fd);

                struct epoll_event ev;
                ev.events = EPOLLIN | EPOLLET;
                ev.data.fd = client_fd;
                epoll_ctl(poller_fd, EPOLL_CTL_ADD, client_fd, &ev);
            }
        } else {
            if (events[i].events & (EPOLLERR | EPOLLHUP)) {
                close(fd);
                continue;
            }

            while (1) {
                ssize_t bytes_read = read(fd, buf, sizeof(buf) - 1);
                if (bytes_read > 0) {
                    buf[bytes_read] = '\0';
                    parse_and_dispatch(fd, buf, (int)bytes_read, cb);
                    processed_events++;
                } else {
                    if (bytes_read < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                        break;
                    }
                    close(fd);
                    break;
                }
            }
        }
    }
#endif

    return processed_events;
}
