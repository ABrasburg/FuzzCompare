#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef __cplusplus
extern "C" {
#endif

extern int LLVMFuzzerTestOneInput(const unsigned char *data, unsigned long size);

#ifdef __cplusplus
}
#endif

static void run_file(const char *path)
{
	FILE *f = fopen(path, "rb");
	if (!f)
		return;

	if (fseek(f, 0, SEEK_END) != 0) {
		fclose(f);
		return;
	}
	long n = ftell(f);
	if (n < 0) {
		fclose(f);
		return;
	}
	rewind(f);

	unsigned char *buf = (unsigned char *)malloc((size_t)n + 1);
	if (!buf) {
		fclose(f);
		return;
	}
	size_t got = fread(buf, 1, (size_t)n, f);
	fclose(f);
	LLVMFuzzerTestOneInput(buf, (unsigned long)got);
	free(buf);
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "uso: %s <directorio> [directorio...]\n", argv[0]);
		return 2;
	}

	for (int a = 1; a < argc; a++) {
		struct stat st;
		if (stat(argv[a], &st) != 0 || !S_ISDIR(st.st_mode)) {
			run_file(argv[a]);
			continue;
		}

		DIR *d = opendir(argv[a]);
		if (!d)
			continue;

		struct dirent *e;
		while ((e = readdir(d)) != NULL) {
			if (e->d_name[0] == '.')
				continue;
			char path[4096];
			if (snprintf(path, sizeof path, "%s/%s", argv[a], e->d_name) >= (int)sizeof path)
				continue;
			run_file(path);
		}
		closedir(d);
	}
	return 0;
}

