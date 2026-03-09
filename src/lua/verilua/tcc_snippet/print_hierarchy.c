#include <stdio.h>
#include <string.h>
#include <vpi_user.h>

typedef void (*hierarchy_item_cb_t)(const char *full_path, const char *name, int level);

static void collect_hierarchy_recursive(
    vpiHandle module,
    const char *parent_path,
    int level,
    int max_level,
    hierarchy_item_cb_t cb
) {
    if (max_level != 0 && level > max_level) {
        return;
    }

    vpiHandle iter = vpi_iterate(vpiModule, module);
    if (iter == NULL) {
        return;
    }

    vpiHandle child_module;
    while ((child_module = vpi_scan(iter)) != NULL) {
        const char *name = vpi_get_str(vpiName, child_module);
        if (name == NULL) {
            continue;
        }

        char full_path[4096];
        if (parent_path != NULL && parent_path[0] != '\0') {
            snprintf(full_path, sizeof(full_path), "%s.%s", parent_path, name);
        } else {
            snprintf(full_path, sizeof(full_path), "%s", name);
        }

        cb(full_path, name, level);
        collect_hierarchy_recursive(child_module, full_path, level + 1, max_level, cb);
    }
}

void collect_hierarchy(vpiHandle ref, int max_level, void *cb_raw) {
    if (cb_raw == NULL) {
        return;
    }
    hierarchy_item_cb_t cb = (hierarchy_item_cb_t)cb_raw;
    collect_hierarchy_recursive(ref, "", 0, max_level, cb);
}
