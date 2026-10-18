/* Diagnostic filter only, included after the frozen bound-call helpers.
 * Vector3 offsets/sizes below are generated from the exact official API dump. */
_Static_assert(sizeof(float) == 4 && sizeof(double) == 8 && FLT_RADIX == 2, "single Vector3 / double GD scalar");
_Static_assert(FILTER_SIZE_VECTOR3 == 12 && FILTER_SIZE_VARIANT <= sizeof(Storage), "pinned float_64 ABI");

enum { KEY_NORMAL, KEY_POSITION, KEY_INDICES, KEY_HITS, KEY_DEPTHS, KEY_FLAGS,
    KEY_ORIGINS, KEY_QUERIES, KEY_SKIPS, KEY_MAX_DEPTH, FILTER_KEY_COUNT };
static Storage filter_keys[FILTER_KEY_COUNT], append_name;
static GDExtensionVariantFromTypeConstructorFunc filter_from_vec3, filter_from_int, filter_from_double;
static GDExtensionTypeFromVariantConstructorFunc filter_to_vec3, filter_to_double;

static float component(const void *vector, size_t offset) {
    float value;
    memcpy(&value, (const unsigned char *)vector + offset, sizeof(value));
    return value;
}
static void store_vec3(void *destination, float x, float y, float z) {
    memcpy((unsigned char *)destination + FILTER_VECTOR3_X_OFFSET, &x, sizeof(x));
    memcpy((unsigned char *)destination + FILTER_VECTOR3_Y_OFFSET, &y, sizeof(y));
    memcpy((unsigned char *)destination + FILTER_VECTOR3_Z_OFFSET, &z, sizeof(z));
}
static int64_t variant_size(GDExtensionConstVariantPtr value) {
    Storage result;
    GDExtensionCallError error;
    int64_t size = -1;
    api_variant_call((GDExtensionVariantPtr)value, &size_name, NULL, 0, &result, &error);
    if (error.error == GDEXTENSION_CALL_OK) to_int(&size, &result);
    api_variant_destroy(&result);
    return size;
}
static void resize_variant(Storage *value, int64_t count) {
    Storage length, result;
    GDExtensionCallError error;
    filter_from_int(&length, &count);
    const GDExtensionConstVariantPtr arguments[] = {&length};
    api_variant_call(value, &resize_name, arguments, 1, &result, &error);
    api_variant_destroy(&result);
    api_variant_destroy(&length);
}
static void packed_new(Storage *packed, GDExtensionVariantType type, int64_t count) {
    Storage value;
    GDExtensionCallError error;
    api_variant_construct(type, &value, NULL, 0, &error);
    resize_variant(&value, count);
    api_get_variant_to_type_constructor(type)(packed, &value);
    api_variant_destroy(&value); /* Unique packed owner before mutable pointer access. */
}
static void dictionary_set(Storage *dictionary, int key, GDExtensionConstVariantPtr value) {
    GDExtensionBool valid = 0;
    api_variant_set_keyed(dictionary, &filter_keys[key], value, &valid);
}
static void dictionary_int(Storage *dictionary, int key, int64_t value) {
    Storage variant;
    filter_from_int(&variant, &value);
    dictionary_set(dictionary, key, &variant);
    api_variant_destroy(&variant);
}
static void dictionary_double(Storage *dictionary, int key, double value) {
    Storage variant;
    filter_from_double(&variant, &value);
    dictionary_set(dictionary, key, &variant);
    api_variant_destroy(&variant);
}
static void dictionary_packed(Storage *dictionary, int key, Storage *packed,
        GDExtensionVariantType type, int64_t final_size) {
    Storage value;
    api_get_variant_from_type_constructor(type)(&value, packed);
    api_variant_get_ptr_destructor(type)(packed);
    if (final_size >= 0) resize_variant(&value, final_size);
    dictionary_set(dictionary, key, &value);
    api_variant_destroy(&value);
}

static void filter_layer(void *data, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt count,
        GDExtensionVariantPtr returned, GDExtensionCallError *error) {
    (void)data; (void)instance;
    *error = (GDExtensionCallError){GDEXTENSION_CALL_OK, 0, 0};
    const GDExtensionVariantType types[11] = {
        GDEXTENSION_VARIANT_TYPE_OBJECT, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
        GDEXTENSION_VARIANT_TYPE_VECTOR3, GDEXTENSION_VARIANT_TYPE_VECTOR3,
        GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY, GDEXTENSION_VARIANT_TYPE_INT,
        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT,
        GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT
    };
    if (count != 11 || !ray_bind) { error->error = GDEXTENSION_CALL_ERROR_INVALID_METHOD; return; }
    for (int i = 0; i < 11; ++i) {
        if (api_variant_get_type(args[i]) != types[i]) {
            error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
            error->argument = i; error->expected = types[i]; return;
        }
    }
    GDExtensionObjectPtr tree_object = api_object_get_instance_from_id(api_variant_get_object_instance_id(args[0]));
    if (!tree_object || !api_object_cast_to(tree_object, triangle_tag)) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return;
    }
    int64_t columns, rows;
    double sign_z, margin, scale, initial_max_depth;
    to_int(&columns, (GDExtensionVariantPtr)args[5]);
    to_int(&rows, (GDExtensionVariantPtr)args[6]);
    filter_to_double(&sign_z, (GDExtensionVariantPtr)args[7]);
    filter_to_double(&margin, (GDExtensionVariantPtr)args[8]);
    filter_to_double(&scale, (GDExtensionVariantPtr)args[9]);
    filter_to_double(&initial_max_depth, (GDExtensionVariantPtr)args[10]);
    int64_t length = variant_size(args[1]);
    if (length < 0 || length > INT32_MAX || columns < 1 || rows < 1 || columns > INT64_MAX / rows ||
            variant_size(args[4]) != columns * rows || (sign_z != 1.0 && sign_z != -1.0) ||
            !isfinite(margin) || margin < 0 || !isfinite(scale) || scale <= 0 || !isfinite((float)scale)) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; return;
    }
    Storage body, depth_bounds, lower, upper;
    api_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY)(&body, (GDExtensionVariantPtr)args[1]);
    api_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY)(&depth_bounds, (GDExtensionVariantPtr)args[4]);
    filter_to_vec3(&lower, (GDExtensionVariantPtr)args[2]);
    filter_to_vec3(&upper, (GDExtensionVariantPtr)args[3]);
    double lx = component(&lower, FILTER_VECTOR3_X_OFFSET), ly = component(&lower, FILTER_VECTOR3_Y_OFFSET), lz = component(&lower, FILTER_VECTOR3_Z_OFFSET);
    double ux = component(&upper, FILTER_VECTOR3_X_OFFSET), uy = component(&upper, FILTER_VECTOR3_Y_OFFSET), uz = component(&upper, FILTER_VECTOR3_Z_OFFSET);
    const float *bounds_data = api_packed_float32_array_operator_index_const(&depth_bounds, 0);
    Storage flags, depths, origins, indices, hits, output, direction_native, direction;
    packed_new(&flags, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, length);
    packed_new(&depths, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, length);
    packed_new(&origins, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, length);
    packed_new(&indices, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, length);
    uint8_t *flag_data = length ? api_packed_byte_array_operator_index(&flags, 0) : NULL;
    double *depth_data = length ? api_packed_float64_array_operator_index(&depths, 0) : NULL;
    int32_t *index_data = length ? api_packed_int32_array_operator_index(&indices, 0) : NULL;
    if (length) {
        memset(flag_data, 0, (size_t)length);
        memset(depth_data, 0, (size_t)length * sizeof(double));
        memset(api_packed_vector3_array_operator_index(&origins, 0), 0, (size_t)length * FILTER_SIZE_VECTOR3);
    }
    GDExtensionCallError call_error;
    api_variant_construct(GDEXTENSION_VARIANT_TYPE_ARRAY, &hits, NULL, 0, &call_error);
    api_variant_construct(GDEXTENSION_VARIANT_TYPE_DICTIONARY, &output, NULL, 0, &call_error);
    store_vec3(&direction_native, 0.0f, 0.0f, (float)-sign_z);
    filter_from_vec3(&direction, &direction_native);
    int64_t queries = 0, skips = 0, kept = 0;
    double max_depth = initial_max_depth;
    const float scale32 = (float)scale;
    for (int64_t i = 0; i < length; ++i) {
        const void *point = api_packed_vector3_array_operator_index_const(&body, i);
        const float px = component(point, FILTER_VECTOR3_X_OFFSET), py = component(point, FILTER_VECTOR3_Y_OFFSET), pz = component(point, FILTER_VECTOR3_Z_OFFSET);
        if (px < lx || px > ux || py < ly || py > uy) continue; /* flag0 XY */
        if ((sign_z > 0 && pz < lz - margin) || (sign_z < 0 && pz > uz + margin)) { flag_data[i] = 1; continue; }
        int64_t cell_x = (int64_t)floor(((double)px - lx) * 25.0);
        int64_t cell_y = (int64_t)floor(((double)py - ly) * 25.0);
        cell_x = cell_x < 0 ? 0 : (cell_x > columns - 1 ? columns - 1 : cell_x);
        cell_y = cell_y < 0 ? 0 : (cell_y > rows - 1 ? rows - 1 : cell_y);
        if ((double)pz * sign_z <= (double)bounds_data[cell_y * columns + cell_x] - margin) { flag_data[i] = 2; ++skips; continue; }
        /* Actual Vector3 add then scalar-multiply, each in single precision. */
        float ox = px + 0.0f, oy = py + 0.0f, oz = pz + (float)sign_z;
        ox = ox * scale32; oy = oy * scale32; oz = oz * scale32;
        Storage origin_native, origin, hit, normal, normal_native;
        store_vec3(&origin_native, ox, oy, oz);
        store_vec3(api_packed_vector3_array_operator_index(&origins, i), ox, oy, oz);
        filter_from_vec3(&origin, &origin_native);
        const GDExtensionConstVariantPtr ray_arguments[] = {&origin, &direction};
        ++queries;
        api_object_method_bind_call(ray_bind, tree_object, ray_arguments, 2, &hit, &call_error);
        api_variant_destroy(&origin);
        GDExtensionBool valid = 0;
        api_variant_get_keyed(&hit, &filter_keys[KEY_NORMAL], &normal, &valid);
        if (!valid) {
            flag_data[i] = 3; /* Original bound wrapper returns {} iff no hit. */
            api_variant_destroy(&normal); api_variant_destroy(&hit); continue;
        }
        filter_to_vec3(&normal_native, &normal);
        const double normal_z = component(&normal_native, FILTER_VECTOR3_Z_OFFSET);
        api_variant_destroy(&normal);
        if (fabs(normal_z) < .35) { flag_data[i] = 4; api_variant_destroy(&hit); continue; }
        Storage position, position_native;
        api_variant_get_keyed(&hit, &filter_keys[KEY_POSITION], &position, &valid);
        filter_to_vec3(&position_native, &position);
        const double hit_z = component(&position_native, FILTER_VECTOR3_Z_OFFSET);
        api_variant_destroy(&position);
        const double depth = sign_z * ((double)pz - hit_z / scale);
        depth_data[i] = depth;
        /* Godot VariantUtilityFunctions::maxf -> MAX: equal chooses right,
         * including signed zero. Do not substitute fmax or > assignment. */
        max_depth = max_depth > depth ? max_depth : depth;
        if (depth < -margin + .00025) { flag_data[i] = 5; api_variant_destroy(&hit); continue; }
        flag_data[i] = 6;
        index_data[kept++] = (int32_t)i;
        const GDExtensionConstVariantPtr append_args[] = {&hit};
        Storage append_result;
        api_variant_call(&hits, &append_name, append_args, 1, &append_result, &call_error);
        api_variant_destroy(&append_result); api_variant_destroy(&hit);
    }
    dictionary_packed(&output, KEY_INDICES, &indices, GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY, kept);
    dictionary_packed(&output, KEY_FLAGS, &flags, GDEXTENSION_VARIANT_TYPE_PACKED_BYTE_ARRAY, -1);
    dictionary_packed(&output, KEY_DEPTHS, &depths, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY, -1);
    dictionary_packed(&output, KEY_ORIGINS, &origins, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, -1);
    dictionary_set(&output, KEY_HITS, &hits);
    dictionary_int(&output, KEY_QUERIES, queries);
    dictionary_int(&output, KEY_SKIPS, skips);
    dictionary_double(&output, KEY_MAX_DEPTH, max_depth);
    api_variant_destroy(&hits); api_variant_destroy(&direction);
    api_variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY)(&body);
    api_variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY)(&depth_bounds);
    return_copy(returned, &output);
}

static void filter_register(void) {
    filter_from_vec3 = api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_VECTOR3);
    filter_from_int = api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_INT);
    filter_from_double = api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_FLOAT);
    filter_to_vec3 = api_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_VECTOR3);
    filter_to_double = api_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_FLOAT);
    const char *keys[] = {"normal", "position", "indices", "hits", "depths", "flags", "origins", "raw_queries", "broadphase_skips", "max_contact_depth"};
    for (int i = 0; i < FILTER_KEY_COUNT; ++i) {
        Storage string;
        api_string_new_with_utf8_chars(&string, keys[i]);
        api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_STRING)(&filter_keys[i], &string);
        destroy_string(&string);
    }
    api_string_name_new_with_utf8_chars(&append_name, "append");
    Storage method_name_local, names[11];
    api_string_name_new_with_utf8_chars(&method_name_local, "filter_layer");
    const char *names_text[] = {"tree", "body_points", "lower", "upper", "depth_bounds", "columns", "rows", "sign_z", "margin", "scale", "initial_max_depth"};
    const GDExtensionVariantType types[] = {GDEXTENSION_VARIANT_TYPE_OBJECT, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
        GDEXTENSION_VARIANT_TYPE_VECTOR3, GDEXTENSION_VARIANT_TYPE_VECTOR3, GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT32_ARRAY,
        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT,
        GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT};
    GDExtensionPropertyInfo arguments[11];
    for (int i = 0; i < 11; ++i) {
        api_string_name_new_with_utf8_chars(&names[i], names_text[i]);
        arguments[i] = property(types[i], &names[i], i == 0 ? &triangle_class : &empty_name);
    }
    GDExtensionPropertyInfo returns = property(GDEXTENSION_VARIANT_TYPE_DICTIONARY, &empty_name, &empty_name);
    GDExtensionClassMethodArgumentMetadata metadata[11] = {0};
    GDExtensionClassMethodInfo method = {0};
    method.name = &method_name_local; method.call_func = filter_layer;
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC | GDEXTENSION_METHOD_FLAG_VARARG;
    method.has_return_value = 1; method.return_value_info = &returns;
    method.argument_count = 11; method.arguments_info = arguments; method.arguments_metadata = metadata;
    api_classdb_register_extension_class_method(library, &class_name, &method);
    for (int i = 0; i < 11; ++i) destroy_string_name(&names[i]);
    destroy_string_name(&method_name_local);
}
static void filter_cleanup(void) {
    for (int i = 0; i < FILTER_KEY_COUNT; ++i) api_variant_destroy(&filter_keys[i]);
    destroy_string_name(&append_name);
}
