/* Isolated cached-MethodBind variant of native_triangle_batch.c (2c7ae034).
 * Original engine bound call only; no intersection implementation. */
#include "vendor/gdextension_interface.h"
#include <stddef.h>
#include <math.h>
#include <float.h>
#include "filter_abi.h"
#include <stdint.h>
#include <string.h>

/* Opaque over-allocation, never an inspection of a Godot builtin's layout.
 * Limited to the pinned official arm64 engine; no portable ABI-size claim. */
typedef union { max_align_t alignment; unsigned char bytes[64]; } Storage;
static GDExtensionClassLibraryPtr library;
#define API(type, name) static GDExtensionInterface##type api_##name
API(VariantNewCopy, variant_new_copy);
API(VariantDestroy, variant_destroy);
API(VariantGetType, variant_get_type);
API(VariantGetObjectInstanceId, variant_get_object_instance_id);
API(ObjectGetInstanceFromId, object_get_instance_from_id);
API(ObjectCastTo, object_cast_to);
API(ClassdbGetClassTag, classdb_get_class_tag);
API(VariantConstruct, variant_construct);
API(VariantCall, variant_call);
API(VariantGetIndexed, variant_get_indexed);
API(VariantSetIndexed, variant_set_indexed);
API(GetVariantToTypeConstructor, get_variant_to_type_constructor);
API(StringNameNewWithUtf8Chars, string_name_new_with_utf8_chars);
API(StringNewWithUtf8Chars, string_new_with_utf8_chars);
API(VariantGetPtrDestructor, variant_get_ptr_destructor);
API(ClassdbRegisterExtensionClass6, classdb_register_extension_class6);
API(ClassdbRegisterExtensionClassMethod, classdb_register_extension_class_method);
API(ClassdbUnregisterExtensionClass, classdb_unregister_extension_class);
API(GetGodotVersion2, get_godot_version2);
API(ClassdbGetMethodBind, classdb_get_method_bind);
API(ObjectMethodBindCall, object_method_bind_call);
API(GetVariantFromTypeConstructor, get_variant_from_type_constructor);
API(VariantGetKeyed, variant_get_keyed);
API(VariantSetKeyed, variant_set_keyed);
API(PackedVector3ArrayOperatorIndexConst, packed_vector3_array_operator_index_const);
API(PackedVector3ArrayOperatorIndex, packed_vector3_array_operator_index);
API(PackedFloat32ArrayOperatorIndexConst, packed_float32_array_operator_index_const);
API(PackedFloat64ArrayOperatorIndex, packed_float64_array_operator_index);
API(PackedByteArrayOperatorIndex, packed_byte_array_operator_index);
API(PackedInt32ArrayOperatorIndex, packed_int32_array_operator_index);
API(PackedInt32ArrayOperatorIndexConst, packed_int32_array_operator_index_const);
API(PackedFloat32ArrayOperatorIndex, packed_float32_array_operator_index);

#undef API

static Storage class_name, parent_name, method_name, ray_name, size_name, resize_name;
static Storage arg_names[3], empty_name, empty_string, triangle_class;
static GDExtensionPtrDestructor destroy_string_name, destroy_string;
static GDExtensionTypeFromVariantConstructorFunc to_int;
static void *triangle_tag;
static GDExtensionMethodBindPtr ray_bind;

static void free_never_created(void *data, GDExtensionClassInstancePtr instance) {
    (void)data; (void)instance;
}

static void return_copy(GDExtensionVariantPtr destination, Storage *source) {
    /* A ClassMethodCall return is initialized, unlike variant_call outputs. */
    api_variant_destroy(destination);
    api_variant_new_copy(destination, source);
    api_variant_destroy(source);
}

static void batch_raw(void *data, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt count,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    (void)data; (void)instance;
    *error = (GDExtensionCallError){GDEXTENSION_CALL_OK, 0, 0};
    if (count != 3) {
        error->error = count < 3 ? GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS : GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS;
        error->expected = 3;
        return;
    }
    const GDExtensionVariantType expected[3] = {
        GDEXTENSION_VARIANT_TYPE_OBJECT, GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY,
        GDEXTENSION_VARIANT_TYPE_VECTOR3
    };
    for (int i = 0; i < 3; ++i) {
        if (api_variant_get_type(args[i]) != expected[i]) {
            error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
            error->argument = i;
            error->expected = expected[i];
            return;
        }
    }
    GDExtensionObjectPtr tree_object = api_object_get_instance_from_id(api_variant_get_object_instance_id(args[0]));
    if (!tree_object || !api_object_cast_to(tree_object, triangle_tag)) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->argument = 0; error->expected = GDEXTENSION_VARIANT_TYPE_OBJECT;
        return;
    }
    if (data != NULL && ray_bind == NULL) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_METHOD;
        return;
    }
    Storage tree, output, size_value, resize_result;
    GDExtensionCallError call_error;
    api_variant_new_copy(&tree, args[0]);
    api_variant_construct(GDEXTENSION_VARIANT_TYPE_ARRAY, &output, NULL, 0, &call_error);
    if (call_error.error != GDEXTENSION_CALL_OK) {
        *error = call_error; api_variant_destroy(&output); api_variant_destroy(&tree); return;
    }
    api_variant_call((GDExtensionVariantPtr)args[1], &size_name, NULL, 0, &size_value, &call_error);
    if (call_error.error != GDEXTENSION_CALL_OK) {
        *error = call_error; api_variant_destroy(&size_value); api_variant_destroy(&output); api_variant_destroy(&tree); return;
    }
    int64_t length = 0;
    to_int(&length, &size_value);
    const GDExtensionConstVariantPtr resize_args[] = {&size_value};
    api_variant_call(&output, &resize_name, resize_args, 1, &resize_result, &call_error);
    api_variant_destroy(&resize_result);
    api_variant_destroy(&size_value);
    if (call_error.error != GDEXTENSION_CALL_OK) {
        *error = call_error; api_variant_destroy(&output); api_variant_destroy(&tree); return;
    }
    for (int64_t i = 0; i < length; ++i) {
        Storage origin, hit;
        GDExtensionBool valid = 0, out_of_bounds = 0;
        api_variant_get_indexed(args[1], i, &origin, &valid, &out_of_bounds);
        if (!valid || out_of_bounds) {
            api_variant_destroy(&origin);
            error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
            error->argument = 1;
            error->expected = GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY;
            api_variant_destroy(&output); api_variant_destroy(&tree); return;
        }
        const GDExtensionConstVariantPtr ray_args[] = {&origin, args[2]};
        /* Exactly the engine-bound TriangleMesh.intersect_ray, once per input.
         * No filtering, arithmetic, normalization, scale, sorting or caching. */
        if (data != NULL) {
            api_object_method_bind_call(ray_bind, tree_object, ray_args, 2, &hit, &call_error);
        } else {
            api_variant_call(&tree, &ray_name, ray_args, 2, &hit, &call_error);
        }
        api_variant_destroy(&origin);
        if (call_error.error != GDEXTENSION_CALL_OK) {
            *error = call_error;
            api_variant_destroy(&hit); api_variant_destroy(&output); api_variant_destroy(&tree); return;
        }
        api_variant_set_indexed(&output, i, &hit, &valid, &out_of_bounds);
        api_variant_destroy(&hit);
        if (!valid || out_of_bounds) {
            error->error = GDEXTENSION_CALL_ERROR_INVALID_METHOD;
            api_variant_destroy(&output); api_variant_destroy(&tree); return;
        }
    }
    api_variant_destroy(&tree);
    return_copy(result, &output);
}

static GDExtensionPropertyInfo property(GDExtensionVariantType type, Storage *name, Storage *type_class) {
    GDExtensionPropertyInfo info = {0};
    info.type = type; info.name = name;
    info.class_name = type_class; info.hint_string = &empty_string;
    info.usage = 6; /* PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR */
    return info;
}

static void configure_method_hash(void *data, GDExtensionClassInstancePtr instance,
        const GDExtensionConstVariantPtr *args, GDExtensionInt count,
        GDExtensionVariantPtr result, GDExtensionCallError *error) {
    (void)data; (void)instance;
    *error = (GDExtensionCallError){GDEXTENSION_CALL_OK, 0, 0};
    if (count != 1 || api_variant_get_type(args[0]) != GDEXTENSION_VARIANT_TYPE_INT) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->expected = GDEXTENSION_VARIANT_TYPE_INT;
        return;
    }
    int64_t method_hash = 0;
    to_int(&method_hash, (GDExtensionVariantPtr)args[0]);
    if (method_hash <= 0 || method_hash > UINT32_MAX) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
        error->expected = GDEXTENSION_VARIANT_TYPE_INT;
        return;
    }
    ray_bind = api_classdb_get_method_bind(&triangle_class, &ray_name, method_hash);
    GDExtensionBool found = ray_bind != NULL;
    Storage value;
    api_get_variant_from_type_constructor(GDEXTENSION_VARIANT_TYPE_BOOL)(&value, &found);
    return_copy(result, &value);
}

#include "native_triangle_filter_impl.h"
#include "native_bounds_impl.h"

static void initialize(void *data, GDExtensionInitializationLevel level) {
    (void)data;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    api_string_name_new_with_utf8_chars(&class_name, "NativeTriangleFilter");
    api_string_name_new_with_utf8_chars(&parent_name, "RefCounted");
    api_string_name_new_with_utf8_chars(&method_name, "batch_raw");
    api_string_name_new_with_utf8_chars(&ray_name, "intersect_ray");
    api_string_name_new_with_utf8_chars(&size_name, "size");
    api_string_name_new_with_utf8_chars(&resize_name, "resize");
    api_string_name_new_with_utf8_chars(&empty_name, "");
    api_string_name_new_with_utf8_chars(&triangle_class, "TriangleMesh");
    triangle_tag = api_classdb_get_class_tag(&triangle_class);
    api_string_new_with_utf8_chars(&empty_string, "");
    const char *names[] = {"tree", "origins", "direction"};
    for (int i = 0; i < 3; ++i) api_string_name_new_with_utf8_chars(&arg_names[i], names[i]);
    destroy_string_name = api_variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    destroy_string = api_variant_get_ptr_destructor(GDEXTENSION_VARIANT_TYPE_STRING);
    to_int = api_get_variant_to_type_constructor(GDEXTENSION_VARIANT_TYPE_INT);
    GDExtensionClassCreationInfo6 creation = {0};
    creation.is_abstract = 1; creation.is_exposed = 1;
    creation.free_instance_func = free_never_created;
    api_classdb_register_extension_class6(library, &class_name, &parent_name, &creation);
    GDExtensionPropertyInfo arguments[] = {
        property(GDEXTENSION_VARIANT_TYPE_OBJECT, &arg_names[0], &triangle_class),
        property(GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR3_ARRAY, &arg_names[1], &empty_name),
        property(GDEXTENSION_VARIANT_TYPE_VECTOR3, &arg_names[2], &empty_name)
    };
    GDExtensionClassMethodArgumentMetadata metadata[3] = {0};
    GDExtensionPropertyInfo returns = property(GDEXTENSION_VARIANT_TYPE_ARRAY, &empty_name, &empty_name);
    GDExtensionClassMethodInfo method = {0};
    method.name = &method_name; method.call_func = batch_raw;
    /* VARARG is intentional: no typed ptrcall ABI or Ref<T> layout assumed.
     * The callback nevertheless requires exactly these three typed arguments. */
    method.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_STATIC | GDEXTENSION_METHOD_FLAG_VARARG;
    method.has_return_value = 1; method.return_value_info = &returns;
    method.argument_count = 3; method.arguments_info = arguments; method.arguments_metadata = metadata;
    api_classdb_register_extension_class_method(library, &class_name, &method);
    Storage bound_name, configure_name, hash_name;
    api_string_name_new_with_utf8_chars(&bound_name, "batch_bound");
    method.name = &bound_name;
    method.method_userdata = &ray_bind;
    api_classdb_register_extension_class_method(library, &class_name, &method);
    api_string_name_new_with_utf8_chars(&configure_name, "configure_method_hash");
    api_string_name_new_with_utf8_chars(&hash_name, "method_hash");
    GDExtensionPropertyInfo hash_argument = property(GDEXTENSION_VARIANT_TYPE_INT, &hash_name, &empty_name);
    GDExtensionPropertyInfo bool_return = property(GDEXTENSION_VARIANT_TYPE_BOOL, &empty_name, &empty_name);
    method.name = &configure_name;
    method.call_func = configure_method_hash;
    method.method_userdata = NULL;
    method.argument_count = 1;
    method.arguments_info = &hash_argument;
    method.return_value_info = &bool_return;
    api_classdb_register_extension_class_method(library, &class_name, &method);
    destroy_string_name(&bound_name);
    destroy_string_name(&configure_name);
    destroy_string_name(&hash_name);
    filter_register();
    geometry_register();
}

static void deinitialize(void *data, GDExtensionInitializationLevel level) {
    (void)data;
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    geometry_cleanup();
    filter_cleanup();
    api_classdb_unregister_extension_class(library, &class_name);
    Storage *names[] = {&class_name, &parent_name, &method_name, &ray_name, &size_name,
        &resize_name, &empty_name, &triangle_class, &arg_names[0], &arg_names[1], &arg_names[2]};
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); ++i) destroy_string_name(names[i]);
    destroy_string(&empty_string);
}

__attribute__((visibility("default"))) GDExtensionBool native_triangle_filter_init(
        GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr owner,
        GDExtensionInitialization *initialization) {
#define LOAD(type, name) do { \
    GDExtensionInterfaceFunctionPtr address = get_proc(#name); \
    _Static_assert(sizeof(address) == sizeof(api_##name), "arm64 function pointer size"); \
    memcpy(&api_##name, &address, sizeof(address)); \
    if (!api_##name) return 0; \
} while (0)
    LOAD(VariantNewCopy, variant_new_copy);
    LOAD(VariantDestroy, variant_destroy);
    LOAD(VariantGetType, variant_get_type);
    LOAD(VariantGetObjectInstanceId, variant_get_object_instance_id);
    LOAD(ObjectGetInstanceFromId, object_get_instance_from_id);
    LOAD(ObjectCastTo, object_cast_to);
    LOAD(ClassdbGetClassTag, classdb_get_class_tag);
    LOAD(VariantConstruct, variant_construct);
    LOAD(VariantCall, variant_call);
    LOAD(VariantGetIndexed, variant_get_indexed);
    LOAD(VariantSetIndexed, variant_set_indexed);
    LOAD(GetVariantToTypeConstructor, get_variant_to_type_constructor);
    LOAD(StringNameNewWithUtf8Chars, string_name_new_with_utf8_chars);
    LOAD(StringNewWithUtf8Chars, string_new_with_utf8_chars);
    LOAD(VariantGetPtrDestructor, variant_get_ptr_destructor);
    LOAD(ClassdbRegisterExtensionClass6, classdb_register_extension_class6);
    LOAD(ClassdbRegisterExtensionClassMethod, classdb_register_extension_class_method);
    LOAD(ClassdbUnregisterExtensionClass, classdb_unregister_extension_class);
    LOAD(GetGodotVersion2, get_godot_version2);
    LOAD(ClassdbGetMethodBind, classdb_get_method_bind);
    LOAD(ObjectMethodBindCall, object_method_bind_call);
    LOAD(GetVariantFromTypeConstructor, get_variant_from_type_constructor);
    LOAD(VariantGetKeyed, variant_get_keyed);
    LOAD(VariantSetKeyed, variant_set_keyed);
    LOAD(PackedVector3ArrayOperatorIndexConst, packed_vector3_array_operator_index_const);
    LOAD(PackedVector3ArrayOperatorIndex, packed_vector3_array_operator_index);
    LOAD(PackedFloat32ArrayOperatorIndexConst, packed_float32_array_operator_index_const);
    LOAD(PackedFloat64ArrayOperatorIndex, packed_float64_array_operator_index);
    LOAD(PackedByteArrayOperatorIndex, packed_byte_array_operator_index);
    LOAD(PackedInt32ArrayOperatorIndex, packed_int32_array_operator_index);
    LOAD(PackedInt32ArrayOperatorIndexConst, packed_int32_array_operator_index_const);
    LOAD(PackedFloat32ArrayOperatorIndex, packed_float32_array_operator_index);
#undef LOAD
    GDExtensionGodotVersion2 version = {0};
    api_get_godot_version2(&version);
    if (version.major != 4 || version.minor != 8 || !version.hash || strncmp(version.hash, "c971f93e7", 9) != 0) return 0;
    library = owner;
    initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    initialization->userdata = NULL;
    initialization->initialize = initialize;
    initialization->deinitialize = deinitialize;
    return 1;
}
