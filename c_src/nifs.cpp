#include <erl_nif.h>
#include <stdio.h>
#include <cstddef>
#include <cstdint>

#include "AccountParser.hpp"
#include "miniz.h"

#define MAYBE_UNUSED(x) (void)x

static ERL_NIF_TERM ATOM_OK;
static ERL_NIF_TERM ATOM_ERROR;
static ERL_NIF_TERM ATOM_NIL;
static ERL_NIF_TERM ATOM_NOMEM;

struct MutBin {
    size_t         size;
    unsigned char* data;

    bool do_realloc(size_t new_size) {
        if (new_size > size) {
            this->data = reinterpret_cast<unsigned char*>(realloc(this->data, new_size));
            if (this->data == nullptr) { return false; }
        }
        this->size = new_size;
        return true;
    }
};

struct NifsData {
    ErlNifResourceType* mz_zip_archive_resource_type;
    ErlNifResourceType* mutable_binary_resource_type;
    ErlNifResourceType* parser_resource_type;
};

void nif_mutable_binary_free(ErlNifEnv* /*env*/, void* obj) {
    printf("closing mutbin %p\n", obj);

    if (obj != nullptr) free(obj);
}

void nif_mz_zip_archive_free(ErlNifEnv* /*env*/, void* obj) {
    printf("closing mz_zip %p\n", obj);

    mz_zip_archive* archive = reinterpret_cast<mz_zip_archive*>(obj);
    mz_zip_reader_end(archive);
}

void nif_parser_free(ErlNifEnv* /*env*/, void* obj) {
    if (obj) {
        hlcup::AccountParser* p = reinterpret_cast<hlcup::AccountParser*>(obj);
        delete p;
    }
}

static void open_resources(ErlNifEnv* env, NifsData* data) {
    ErlNifResourceFlags flags          = static_cast<ErlNifResourceFlags>(ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER);
    data->mz_zip_archive_resource_type = enif_open_resource_type(env, nullptr, "mz_zip_archive", nif_mz_zip_archive_free, flags, nullptr);
    data->mutable_binary_resource_type = enif_open_resource_type(env, nullptr, "mutable_binary", nif_mutable_binary_free, flags, nullptr);
    data->parser_resource_type         = enif_open_resource_type(env, nullptr, "hlcup_parser", nif_parser_free, flags, nullptr);
}

/////// mutable binary impl

static ERL_NIF_TERM mutbin_create(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM /*argv*/[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    auto* bin = reinterpret_cast<MutBin*>(enif_alloc_resource(data->mutable_binary_resource_type, sizeof(MutBin)));
    memset(bin, 0, sizeof(MutBin));

    ERL_NIF_TERM ret = enif_make_resource(env, bin);
    //    enif_release_resource(bin);
    return ret;
}

static ERL_NIF_TERM mutbin_get(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    MutBin* bin;
    if (!enif_get_resource(env, argv[0], data->mutable_binary_resource_type, reinterpret_cast<void**>(&bin))) { return enif_make_badarg(env); }

    if (bin->size == 0 || bin->data == nullptr) { return ATOM_NIL; }

    ERL_NIF_TERM   term;
    unsigned char* bin_ptr = enif_make_new_binary(env, bin->size, &term);
    memcpy(bin_ptr, bin->data, bin->size);

    return term;
}

static ERL_NIF_TERM mutbin_free(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    MutBin* bin;
    if (!enif_get_resource(env, argv[0], data->mutable_binary_resource_type, reinterpret_cast<void**>(&bin))) { return enif_make_badarg(env); }

    enif_release_resource(bin);

    return ATOM_OK;
}

////// miniz impl

static ERL_NIF_TERM open_file(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    char      filename[1024];
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    if (!enif_get_string(env, argv[0], filename, 1024, ERL_NIF_LATIN1)) { return enif_make_badarg(env); }

    mz_zip_archive* zip_h = reinterpret_cast<mz_zip_archive*>(enif_alloc_resource(data->mz_zip_archive_resource_type, sizeof(mz_zip_archive)));
    memset(zip_h, 0, sizeof(mz_zip_archive));
    if (!mz_zip_reader_init_file(zip_h, filename, 0)) {
        const char* err_msg = mz_zip_get_error_string(mz_zip_get_last_error(zip_h));
        return enif_make_tuple2(env, ATOM_ERROR, enif_make_string(env, err_msg, ERL_NIF_LATIN1));
    }

    ERL_NIF_TERM zip_h_term = enif_make_resource(env, zip_h);
    //    enif_release_resource(zip_h);
    return enif_make_tuple2(env, ATOM_OK, zip_h_term);
}

static ERL_NIF_TERM num_files(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    mz_zip_archive* zip_h;
    if (!enif_get_resource(env, argv[0], data->mz_zip_archive_resource_type, reinterpret_cast<void**>(&zip_h))) { return enif_make_badarg(env); }

    return enif_make_uint(env, mz_zip_reader_get_num_files(zip_h));
}

static ERL_NIF_TERM read_file(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    mz_zip_archive* zip_h;
    uint            idx;
    MutBin*         bin;
    if (!enif_get_resource(env, argv[0], data->mz_zip_archive_resource_type, reinterpret_cast<void**>(&zip_h))) { return enif_make_badarg(env); }
    if (!enif_get_uint(env, argv[1], &idx)) { return enif_make_badarg(env); }
    if (!enif_get_resource(env, argv[2], data->mutable_binary_resource_type, reinterpret_cast<void**>(&bin))) { return enif_make_badarg(env); }

    mz_zip_archive_file_stat stat;
    mz_zip_reader_file_stat(zip_h, idx, &stat);

    if (!bin->do_realloc(stat.m_uncomp_size)) { return enif_make_tuple2(env, ATOM_ERROR, ATOM_NOMEM); }

    if (!mz_zip_reader_extract_to_mem(zip_h, idx, bin->data, bin->size, 0)) {
        const char* err_msg = mz_zip_get_error_string(mz_zip_get_last_error(zip_h));
        return enif_make_tuple2(env, ATOM_ERROR, enif_make_string(env, err_msg, ERL_NIF_LATIN1));
    }

    return ATOM_OK;
}

static ERL_NIF_TERM close_file(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    mz_zip_archive* zip_h;
    if (!enif_get_resource(env, argv[0], data->mz_zip_archive_resource_type, reinterpret_cast<void**>(&zip_h))) { return enif_make_badarg(env); }

    enif_release_resource(zip_h);

    return ATOM_OK;
}

////////// parser impl

static ERL_NIF_TERM parser_create(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM /*argv*/[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    auto* parser = reinterpret_cast<hlcup::AccountParser*>(enif_alloc_resource(data->parser_resource_type, sizeof(hlcup::AccountParser)));
    new (parser) hlcup::AccountParser();

    ERL_NIF_TERM ret = enif_make_resource(env, parser);
    //    enif_release_resource(bin);
    return ret;
}

static ERL_NIF_TERM parser_set_bin(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    hlcup::AccountParser* parser;
    MutBin*               bin;
    if (!enif_get_resource(env, argv[0], data->parser_resource_type, reinterpret_cast<void**>(&parser))) { return enif_make_badarg(env); }
    if (!enif_get_resource(env, argv[1], data->mutable_binary_resource_type, reinterpret_cast<void**>(&bin))) { return enif_make_badarg(env); }

    parser->p  = reinterpret_cast<char*>(bin->data);
    parser->pe = reinterpret_cast<char*>(bin->data + bin->size);

    return ATOM_OK;
}

static ERL_NIF_TERM parser_set_bin_multi(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    hlcup::AccountParser* parser;
    MutBin*               bin;
    if (!enif_get_resource(env, argv[0], data->parser_resource_type, reinterpret_cast<void**>(&parser))) { return enif_make_badarg(env); }
    if (!enif_get_resource(env, argv[1], data->mutable_binary_resource_type, reinterpret_cast<void**>(&bin))) { return enif_make_badarg(env); }

    parser->p  = reinterpret_cast<char*>(bin->data);
    parser->pe = reinterpret_cast<char*>(bin->data + bin->size);

    while (parser->p < parser->pe && *parser->p != '[') ++parser->p;
    ++parser->p;

    return ATOM_OK;
}

static ERL_NIF_TERM parser_free(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    hlcup::AccountParser* parser;
    if (!enif_get_resource(env, argv[0], data->parser_resource_type, reinterpret_cast<void**>(&parser))) { return enif_make_badarg(env); }

    enif_release_resource(parser);

    return ATOM_OK;
}

static inline ERL_NIF_TERM make_stringref_helper(ErlNifEnv* env, ERL_NIF_TERM bin, const hlcup::StringRef& ref) {
    if (ref.offset == hlcup::Account::kInvalidOffset) { return ATOM_NIL; }
    return enif_make_sub_binary(env, bin, ref.offset, ref.size);
}

static inline ERL_NIF_TERM make_i32_helper(ErlNifEnv* env, hlcup::i32 val) {
    if (val == static_cast<hlcup::i32>(-1)) { return ATOM_NIL; }
    return enif_make_int(env, val);
}

static inline ERL_NIF_TERM make_u32_helper(ErlNifEnv* env, hlcup::u32 val) {
    if (val == static_cast<hlcup::u32>(-1)) { return ATOM_NIL; }
    return enif_make_uint(env, val);
}

static ERL_NIF_TERM parser_parse(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM argv[]) {
    NifsData* data = reinterpret_cast<NifsData*>(enif_priv_data(env));

    hlcup::AccountParser* parser;
    if (!enif_get_resource(env, argv[0], data->parser_resource_type, reinterpret_cast<void**>(&parser))) { return enif_make_badarg(env); }

    parser->account.clear();
    while (parser->p < parser->pe) {
        if (*parser->p == '{') break;
        ++parser->p;
    }

    if (parser->p >= parser->pe || !parser->parse()) { return ATOM_NIL; }

    hlcup::Account& acc = parser->account;
    ERL_NIF_TERM    string_data_term;
    unsigned char*  str_data_ptr = enif_make_new_binary(env, 8192, &string_data_term);
    memcpy(str_data_ptr, acc.string_data, 8192);
    ERL_NIF_TERM interests_term = enif_make_list(env, 0);
    for (hlcup::u32 i = 1; i < acc.interests.size(); ++i) {
        interests_term = enif_make_list_cell(
            env, make_stringref_helper(env, string_data_term, hlcup::StringRef{acc.interests[i - 1], acc.interests[i] - acc.interests[i - 1]}), interests_term);
    }
    return enif_make_tuple(
        env, 13, make_u32_helper(env, acc.id), make_u32_helper(env, acc.sex), make_i32_helper(env, acc.birth), make_i32_helper(env, acc.joined),
        enif_make_tuple2(env, make_i32_helper(env, acc.premium.start), make_i32_helper(env, acc.premium.finish)),
        make_stringref_helper(env, string_data_term, acc.city), make_stringref_helper(env, string_data_term, acc.country),
        make_stringref_helper(env, string_data_term, acc.fname), make_stringref_helper(env, string_data_term, acc.sname),
        make_stringref_helper(env, string_data_term, acc.phone), make_stringref_helper(env, string_data_term, acc.email), interests_term, string_data_term);
}

///////// other

static ERL_NIF_TERM test(ErlNifEnv* env, int /*argc*/, const ERL_NIF_TERM /*argv*/[]) { return enif_make_string(env, "hlcup_miniz test!", ERL_NIF_LATIN1); }

static int on_nif_load(ErlNifEnv* env, void** priv, ERL_NIF_TERM load_info) {
    MAYBE_UNUSED(priv);
    MAYBE_UNUSED(load_info);

    ATOM_OK    = enif_make_atom(env, "ok");
    ATOM_ERROR = enif_make_atom(env, "error");
    ATOM_NIL   = enif_make_atom(env, "nil");
    ATOM_NOMEM = enif_make_atom(env, "nomem");

    NifsData* data = reinterpret_cast<NifsData*>(enif_alloc(sizeof(NifsData)));
    open_resources(env, data);

    *priv = data;

    return 0;
}

static void on_nif_unload(ErlNifEnv* env, void* priv) {
    MAYBE_UNUSED(env);

    enif_free(priv);
}

static int on_nif_upgrade(ErlNifEnv* env, void** priv, void** old_priv, ERL_NIF_TERM info) {
    MAYBE_UNUSED(env);
    MAYBE_UNUSED(priv);
    MAYBE_UNUSED(old_priv);
    MAYBE_UNUSED(info);
    return 0;
}

// clang-format off
static ErlNifFunc nif_funcs[] = {
    {"test", 0, test, 0},

    {"open_file", 1, open_file, 0},
    {"close_file", 1, close_file, 0},
    {"read_file", 3, read_file, 0},
    {"num_files", 1, num_files, 0},

    {"mutbin_create", 0, mutbin_create, 0},
    {"mutbin_get", 1, mutbin_get, 0},
    {"mutbin_free", 1, mutbin_free, 0},

    {"parser_create", 0, parser_create, 0},
    {"parser_free", 1, parser_free, 0},
    {"parser_set_bin", 2, parser_set_bin, 0},
    {"parser_set_bin_multi", 2, parser_set_bin_multi, 0},
    {"parser_parse", 1, parser_parse, 0},
};
// clang-format on

ERL_NIF_INIT(hlcup_nifs, nif_funcs, on_nif_load, NULL, on_nif_upgrade, on_nif_unload);
