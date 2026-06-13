#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>

static void print_usage(void) {
    fputs("Usage: roothelper [-w workdir] -c \"command\"\n", stderr);
}

/// POSIX shell 单引号转义（调用方需 free）
static char *shell_single_quote(const char *s) {
    size_t len = strlen(s);
    char *out = malloc(len * 4 + 3);
    if (!out) return NULL;

    char *p = out;
    *p++ = '\'';
    for (size_t i = 0; i < len; i++) {
        if (s[i] == '\'') {
            *p++ = '\'';
            *p++ = '\\';
            *p++ = '\'';
            *p++ = '\'';
        } else {
            *p++ = s[i];
        }
    }
    *p++ = '\'';
    *p = '\0';
    return out;
}

int main(int argc, char *argv[]) {
    const char *workdir = NULL;
    const char *command = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-w") == 0 && i + 1 < argc) {
            workdir = argv[++i];
        } else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
            command = argv[++i];
        } else {
            print_usage();
            return 1;
        }
    }

    if (!command) {
        print_usage();
        return 1;
    }

    char *final_cmd = NULL;
    if (workdir) {
        char *wd = shell_single_quote(workdir);
        if (!wd) return 127;
        size_t n = strlen(wd) + strlen(command) + 16;
        final_cmd = malloc(n);
        if (!final_cmd) { free(wd); return 127; }
        snprintf(final_cmd, n, "cd %s && %s", wd, command);
        free(wd);
    } else {
        final_cmd = strdup(command);
        if (!final_cmd) return 127;
    }

    const char *theos = getenv("THEOS");
    if (theos && theos[0]) {
        char path_buf[4096];
        const char *cur = getenv("PATH");
        snprintf(path_buf, sizeof(path_buf), "%s/bin:/usr/local/bin:/usr/bin:/bin:%s",
                 theos, cur ? cur : "");
        setenv("PATH", path_buf, 1);
    }
    if (!getenv("LANG")) {
        setenv("LANG", "C.UTF-8", 1);
    }
    setenv("PYTHONUNBUFFERED", "1", 1);

    int devnull = open("/dev/null", O_RDONLY);
    if (devnull >= 0) {
        dup2(devnull, STDIN_FILENO);
        close(devnull);
    }

    char *sh_argv[] = { "/bin/sh", "-c", final_cmd, NULL };
    execv("/bin/sh", sh_argv);

    fprintf(stderr, "roothelper execv failed: %s\n", strerror(errno));
    free(final_cmd);
    return 127;
}
