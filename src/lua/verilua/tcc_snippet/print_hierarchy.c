#include <string.h>
#include <assert.h>
#include <stdio.h>
#include <vpi_user.h>


void do_print_hierarchy(vpiHandle module, int level, int max_level) {
    vpiHandle iter, child_module;

    char prefix[256] = {0};
    for (int i = 0; i < level; i++)
        strcat(prefix, "\t┃");

    if(level != 0)
        strcat(prefix, "➔ ");

    iter = vpi_iterate(vpiModule, module);
    if (iter == NULL) {
        return;  
    }

    while ((child_module = vpi_scan(iter)) != NULL) {
        if(level <= max_level || max_level == 0)
            printf("%s [%d] %s\n", prefix, level, vpi_get_str(vpiName, child_module));
        do_print_hierarchy(child_module, level + 1, max_level);
    }
}

// typedef unsigned int    PLI_UINT32;
// typedef PLI_UINT32 *vpiHandle;
void print_hierarchy(vpiHandle ref, int max_level) {
    char str[256] = {0};

    if (ref != NULL) {
        vpiHandle hdl = vpi_iterate(vpiModule, ref);
        assert(hdl != NULL);
        
        sprintf(str, "▂▂▂▂▂ print module hierarchy ref: %s max_level: %d ▂▂▂▂▂\n", vpi_get_str(vpiName, hdl), max_level);
        printf("%s", str);
    } else {
        sprintf(str, "▂▂▂▂▂ print module hierarchy max_level: %d ▂▂▂▂▂\n", max_level);
        printf("%s",str);
    }
    do_print_hierarchy(ref, 0, max_level);

    printf("\n");
}

