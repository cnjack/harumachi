/* Evidence-only exact layer bounds/grid constructor. No contact/constraint code. */
enum { GEOM_VALID, GEOM_LOWER, GEOM_UPPER, GEOM_COLUMNS, GEOM_ROWS,
    GEOM_DEPTH_BOUNDS, GEOM_KEY_COUNT };
static Storage geometry_keys[GEOM_KEY_COUNT];

static void geometry_set(Storage *output, int key, GDExtensionConstVariantPtr value) {
    GDExtensionBool valid = 0;
    api_variant_set_keyed(output, &geometry_keys[key], value, &valid);
}
static void geometry_integer(Storage *output, int key, int64_t integer) {
    Storage value;
    filter_from_int(&value, &integer);
    geometry_set(output, key, &value);
    api_variant_destroy(&value);
}
static void geometry_bool(Storage *output, GDExtensionBool valid) {
    Storage value;
    api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_BOOL)(&value, &valid);
    geometry_set(output, GEOM_VALID, &value);
    api_variant_destroy(&value);
}
static void geometry_vector(Storage *output, int key, const float point[3]) {
    Storage native, value;
    store_vec3(&native, point[0], point[1], point[2]);
    filter_from_vec3(&value, &native);
    geometry_set(output, key, &value);
    api_variant_destroy(&value);
}
/* Match MIN/MAX's equal-right choice; do not use fmin/fmax or reassociate. */
static float geometry_min32(float first, float second) { return first < second ? first : second; }
static float geometry_max32(float first, float second) { return first > second ? first : second; }
static double geometry_min64(double first, double second) { return first < second ? first : second; }
static int64_t geometry_clamp(int64_t value, int64_t maximum) {
    return value < 0 ? 0 : (value > maximum ? maximum : value);
}
static int geometry_read_point(Storage *points, int64_t index, float point[3]) {
    const void *value = api_packed_vector3_array_operator_index_const(points, index);
    point[0] = component(value, FILTER_VECTOR3_X_OFFSET);
    point[1] = component(value, FILTER_VECTOR3_Y_OFFSET);
    point[2] = component(value, FILTER_VECTOR3_Z_OFFSET);
    return isfinite(point[0]) && isfinite(point[1]) && isfinite(point[2]);
}

static void build_layer_geometry(void *data, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt count,
        GDExtensionVariantPtr returned, GDExtensionCallError *error) {
    (void)data; (void)instance;
    *error = (GDExtensionCallError){GDEXTENSION_CALL_OK, 0, 0};
    const GDExtensionVariantType types[4] = {
        GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
        GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,
        GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,
        GDEXTENSION_VARIANT_TYPE_FLOAT
    };
    if (count != 4) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return; }
    for (int i = 0; i < 4; ++i) {
        if (api_variant_get_type(args[i]) != types[i]) {
            error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
            error->argument = i; error->expected = types[i]; return;
        }
    }
    Storage output;
    GDExtensionCallError construction_error;
    api_variant_construct(GDEXTENSION_VARIANT_TYPE_DICTIONARY, &output, NULL, 0, &construction_error);
    geometry_bool(&output, 0);
    const int64_t point_count = variant_size(args[0]);
    const int64_t panel_count = variant_size(args[1]);
    const int64_t corner_count = variant_size(args[2]);
    double sign_z;
    filter_to_double(&sign_z, (GDExtensionVariantPtr)args[3]);
    if (point_count <= 0 || panel_count <= 0 || corner_count <= 0 || corner_count % 3 ||
            point_count > INT32_MAX || (sign_z != 1.0 && sign_z != -1.0)) {
        return_copy(returned, &output); return;
    }
    Storage points, panel, triangles;
    api_get_variant_to_type_constructor(types[0])(&points, (GDExtensionVariantPtr)args[0]);
    api_get_variant_to_type_constructor(types[1])(&panel, (GDExtensionVariantPtr)args[1]);
    api_get_variant_to_type_constructor(types[2])(&triangles, (GDExtensionVariantPtr)args[2]);
    const int32_t *panel_ids = api_packed_int32_array_operator_index_const(&panel, 0);
    const int32_t *triangle_ids = api_packed_int32_array_operator_index_const(&triangles, 0);
    float lower[3] = {INFINITY, INFINITY, INFINITY};
    float upper[3] = {-INFINITY, -INFINITY, -INFINITY};
    for (int64_t index = 0; index < panel_count; ++index) {
        const int32_t vertex = panel_ids[index];
        float point[3];
        if (vertex < 0 || vertex >= point_count || !geometry_read_point(&points, vertex, point)) goto cleanup;
        for (int axis = 0; axis < 3; ++axis) {
            lower[axis] = geometry_min32(lower[axis], point[axis]);
            upper[axis] = geometry_max32(upper[axis], point[axis]);
        }
    }
    /* Vector3 components promote to GD's double scalar before subtraction. */
    const double column_extent = ((double)upper[0] - (double)lower[0]) * 25.0;
    const double row_extent = ((double)upper[1] - (double)lower[1]) * 25.0;
    if (!isfinite(column_extent) || !isfinite(row_extent) ||
            column_extent > (double)(INT32_MAX - 1) || row_extent > (double)(INT32_MAX - 1)) goto cleanup;
    int64_t columns = (int64_t)ceil(column_extent) + 1;
    int64_t rows = (int64_t)ceil(row_extent) + 1;
    if (columns < 1) columns = 1;
    if (rows < 1) rows = 1;
    if (columns > INT32_MAX / rows) goto cleanup;
    Storage depth_bounds;
    packed_new(&depth_bounds, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, columns * rows);
    float *depth = api_packed_float32_array_operator_index(&depth_bounds, 0);
    for (int64_t cell = 0; cell < columns * rows; ++cell) depth[cell] = INFINITY;
    int valid = 1;
    for (int64_t offset = 0; offset < corner_count; offset += 3) {
        float a[3], b[3], c[3];
        for (int corner = 0; corner < 3; ++corner) {
            const int32_t vertex = triangle_ids[offset + corner];
            float *point = corner == 0 ? a : (corner == 1 ? b : c);
            if (vertex < 0 || vertex >= point_count || !geometry_read_point(&points, vertex, point)) { valid = 0; break; }
        }
        if (!valid) break;
        float triangle_lower[3], triangle_upper[3];
        for (int axis = 0; axis < 3; ++axis) {
            triangle_lower[axis] = geometry_min32(geometry_min32(a[axis], b[axis]), c[axis]);
            triangle_upper[axis] = geometry_max32(geometry_max32(a[axis], b[axis]), c[axis]);
            if (triangle_lower[axis] < lower[axis] || triangle_upper[axis] > upper[axis]) valid = 0;
        }
        if (!valid) break; /* Malformed panel cannot cause an out-of-range floor cast. */
        const double signed_lower = geometry_min64((double)a[2] * sign_z,
                geometry_min64((double)b[2] * sign_z, (double)c[2] * sign_z));
        const int64_t first_x = geometry_clamp((int64_t)floor((((double)triangle_lower[0] - (double)lower[0]) - .000001) * 25.0), columns - 1);
        const int64_t last_x = geometry_clamp((int64_t)floor((((double)triangle_upper[0] - (double)lower[0]) + .000001) * 25.0), columns - 1);
        const int64_t first_y = geometry_clamp((int64_t)floor((((double)triangle_lower[1] - (double)lower[1]) - .000001) * 25.0), rows - 1);
        const int64_t last_y = geometry_clamp((int64_t)floor((((double)triangle_upper[1] - (double)lower[1]) + .000001) * 25.0), rows - 1);
        for (int64_t cell_y = first_y; cell_y <= last_y; ++cell_y) {
            for (int64_t cell_x = first_x; cell_x <= last_x; ++cell_x) {
                const int64_t cell = cell_y * columns + cell_x;
                depth[cell] = (float)geometry_min64((double)depth[cell], signed_lower);
            }
        }
    }
    if (valid) {
        geometry_vector(&output, GEOM_LOWER, lower);
        geometry_vector(&output, GEOM_UPPER, upper);
        geometry_integer(&output, GEOM_COLUMNS, columns);
        geometry_integer(&output, GEOM_ROWS, rows);
        Storage bounds_value;
        api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY)(&bounds_value, &depth_bounds);
        geometry_set(&output, GEOM_DEPTH_BOUNDS, &bounds_value);
        api_variant_destroy(&bounds_value);
        geometry_bool(&output, 1);
    }
    api_variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY)(&depth_bounds);
cleanup:
    api_variant_get_ptr_destructor(types[0])(&points);
    api_variant_get_ptr_destructor(types[1])(&panel);
    api_variant_get_ptr_destructor(types[2])(&triangles);
    return_copy(returned, &output);
}

static void geometry_register(void) {
    const char *keys[] = {"valid", "lower", "upper", "columns", "rows", "depth_bounds"};
    for (int i = 0; i < GEOM_KEY_COUNT; ++i) {
        Storage text;
        api_string_new_with_utf8_chars(&text, keys[i]);
        api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_STRING)(&geometry_keys[i], &text);
        destroy_string(&text);
    }
    Storage name, names[4];
    api_string_name_new_with_utf8_chars(&name, "build_layer_geometry");
    const char *labels[] = {"posed", "panel_vertices", "triangles", "sign_z"};
    const GDExtensionVariantType types[] = {GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
        GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,
        GDEXTENSION_VARIANT_TYPE_FLOAT};
    GDExtensionPropertyInfo arguments[4];
    for (int i = 0; i < 4; ++i) {
        api_string_name_new_with_utf8_chars(&names[i], labels[i]);
        arguments[i] = property(types[i], &names[i], &empty_name);
    }
    GDExtensionPropertyInfo returns = property(GDEXTENSION_VARIANT_TYPE_DICTIONARY, &empty_name, &empty_name);
    GDExtensionClassMethodArgumentMetadata metadata[4] = {0};
    GDExtensionClassMethodInfo method = {0};
    method.name = &name; method.call_func = build_layer_geometry;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC | GDEXTENSION_METHOD_FLAG_VARARG;
    method.has_return_value = 1; method.return_value_info = &returns;
    method.argument_count = 4; method.arguments_info = arguments; method.arguments_metadata = metadata;
    api_classdb_register_extension_class_method(library, &class_name, &method);
    for (int i = 0; i < 4; ++i) destroy_string_name(&names[i]);
    destroy_string_name(&name);
}
static void geometry_cleanup(void) {
    for (int i = 0; i < GEOM_KEY_COUNT; ++i) api_variant_destroy(&geometry_keys[i]);
}
