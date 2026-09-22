/* See README for what the tools do. */

#include <stddef.h>

/* A string that grows. s is NUL terminated once anything was added. */
struct buf {
    char* s;
    size_t len;
    size_t cap;
};

enum { RUN_QUIET = 1 }; /* run: send the program's stderr to /dev/null */

extern const char* argv0;

void die(const char* fmt, ...);
void warn(const char* fmt, ...);
void* xmalloc(size_t n);
void* xrealloc(void* p, size_t n);
char* xstrdup(const char* s);
char* xstrndup(const char* s, size_t n);

void bufadd(struct buf* b, const char* s, size_t n);
void bufputs(struct buf* b, const char* s);
void bufprintf(struct buf* b, const char* fmt, ...);

int readfd(int fd, struct buf* b);
int readpath(const char* path, struct buf* b);
int writeall(int fd, const char* s, size_t n);
int writepath(const char* path, int flags, const char* s, size_t n);

char* nextline(char** p);
size_t fields(char* line, char** f, size_t max);
char** words(const char* s);
void freewords(char** w);

int have(const char* prog);
int run(char* const argv[], const char* in, struct buf* out, int flags);
char* datafile(const char* env, const char* name);
