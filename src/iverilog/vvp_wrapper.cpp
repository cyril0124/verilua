#include "iverilog/libvvp.h"
#include "lua.hpp"
// #include "lua_vpi.h"
#include <cstddef>
#include <getopt.h>
#include <cstring>
#include <cstdio>
#include <cstdlib>

#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_RESET   "\x1b[0m"

bool version_flag = false;

unsigned module_cnt = 0;
const char*module_tab[64];

int main(int argc, char*argv[]) {
    lua_State *L = luaL_newstate(); // keep luajit symbols
	
	int opt;
	unsigned flag_errors = 0;
	const char *logfile_name = 0x0;

	while ((opt = getopt(argc, argv, "+hil:M:m:nNsvV")) != EOF) switch (opt) {
		case 'h':
			fprintf(stderr,
					"Usage: vvp [options] input-file [+plusargs...]\n"
					"Options:\n"
					" -h             Print this help message.\n"
					" -i             Interactive mode (unbuffered stdio).\n"
					" -l file        Logfile, '-' for <stderr>\n"
					" -M path        VPI module directory\n"
					" -M -           Clear VPI module path\n"
					" -m module      Load vpi module.\n"
					" -n             Non-interactive ($stop = $finish).\n"
					" -N             Same as -n, but exit code is 1 instead of 0\n"
					" -s             $stop right away.\n"
					" -v             Verbose progress messages.\n"
					" -V             Print the version information.\n" );
			exit(0);
		case 'i':
			setvbuf(stdout, 0, _IONBF, 0);
			break;
		case 'l':
			logfile_name = optarg;
			break;
		case 'M':
			if (strcmp(optarg,"-") == 0) {
				vpip_clear_module_paths();
			} else {
				vpip_add_module_path(optarg);
			}
			break;
		case 'm':
			module_tab[module_cnt++] = optarg;
			break;
		case 'n':
			vvp_set_stop_is_finish(true, 0);
			break;
		case 'N':
			vvp_set_stop_is_finish(true, 1);
			break;
		case 's':
			// schedule_stop(0);
			// TODO:
			break;
		case 'v':
			vvp_set_verbose_flag(true);
			break;
		case 'V':
			version_flag = true;
			break;
		default:
			flag_errors += 1;
	}

	if (flag_errors)
		return flag_errors;

	if (version_flag) {
		fprintf(stderr, "Icarus Verilog runtime version " "VERSION" " ("
						"VERSION_TAG" ")\n\n");
		fprintf(stderr, "%s\n\n", "COPYRIGHT");
		fprintf(stderr,
"  This program is free software; you can redistribute it and/or modify\n"
"  it under the terms of the GNU General Public License as published by\n"
"  the Free Software Foundation; either version 2 of the License, or\n"
"  (at your option) any later version.\n"
"\n"
"  This program is distributed in the hope that it will be useful,\n"
"  but WITHOUT ANY WARRANTY; without even the implied warranty of\n"
"  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n"
"  GNU General Public License for more details.\n"
"\n"
"  You should have received a copy of the GNU General Public License along\n"
"  with this program; if not, write to the Free Software Foundation, Inc.,\n"
"  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.\n\n"
);
		return 0;
	}

	if (optind == argc) {
		fprintf(stderr, "%s: no input file.\n", argv[0]);
		return -1;
	}

	vvp_init(logfile_name, argc - optind, argv + optind);

	for (unsigned idx = 0 ;  idx < module_cnt ;  idx += 1)
		vpip_load_module(module_tab[idx]);

	printf("\n[%s:%s:%d] [%sINFO%s] hello from vvp_wrapper\n", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET);

	return vvp_run(argv[optind]);
}