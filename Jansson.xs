#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <jansson.h>

SV* THX_json_t_to_sv(pTHX_ json_t*);
json_t* THX_sv_to_json_t(pTHX_ SV*, json_t*);

json_t*
THX_sv_to_json_t(pTHX_ SV* sv, json_t* json_root)
#define sv_to_json_t(sv, root) THX_sv_to_json_t(aTHX_ sv, root)
{
    /* TODO: leaks memory on exceptions */
    if ( !sv ) {
        return json_null();
    }

    if ( !SvOK(sv) ) {
        return json_null();
    }

    int sv_type = SvTYPE(SvROK(sv) ? SvRV(sv) : sv);
    /* TODO: blessed objects with TO_JSON */
    switch ( sv_type ) {
        case SVt_PVHV:
        {
            json_t* js_obj = json_object();
            HV* hv = MUTABLE_HV(SvRV(sv));
            HE* iter;
            hv_iterinit(hv);
            while ( (iter = hv_iternext(hv)) ) {
                STRLEN len;
                SV* key_sv = hv_iterkeysv(iter);
                SV* val_sv = hv_iterval(hv, iter);
                const char* key_pv = SvPV(key_sv, len);
                json_t *inner_json = sv_to_json_t(val_sv, json_root ? json_root : js_obj);
                json_object_set_new(js_obj, key_pv, inner_json);
            }
            return js_obj;
            break;
        }
        case SVt_PVAV:
        {
            AV* av = MUTABLE_AV(SvRV(sv));
            IV i             = 0;
            json_t* js_array = json_array();
            IV our_av_len    = av_len(av) + 1;
            for ( i = 0; i < our_av_len; i++ ) {
                SV** svp         = av_fetch(av, i, FALSE);
                json_t* inner_obj = (svp && *svp)
                                  ? sv_to_json_t(*svp, json_root ? json_root : js_array)
                                  : json_null();
                json_array_append_new(js_array, inner_obj);
            }
            return js_array;
            break;
        }
        case SVt_PVIV:
            /* fall-through */
        case SVt_IV:
        {
            if ( SvROK(sv) ) {
                if ( json_root ) {
                    json_decref(json_root);
                }
                croak("Unexpected scalar reference %"SVf" in payload, cannot encode", sv);
            }
            json_int_t intv = SvIV(sv);
            return json_integer(intv);
            break;
        }
        case SVt_PVNV:
            /* fall-through */
        case SVt_NV:
        {
            NV nv = SvNV(sv);
            return json_real(nv);
            break;
        }
        case SVt_PV:
        {
            STRLEN len;
            const char *pv = SvPV(sv, len);
            /* pv upgrade to utf8? */
            return json_stringn(pv, len);
            break;
        }
        case SVt_NULL:
            return json_null();
            break;
        case SVt_INVLIST:
            /* fall-through */
        case SVt_REGEXP:
            /* fall-through */
        case SVt_PVCV:
            /* fall-through */
        case SVt_PVGV:
            /* fall-through */
        case SVt_PVIO:
            /* fall-through */
        default:
        {
            croak("Unsupported reference of type %s", sv_reftype(sv, FALSE));
        }
    }
}


SV*
THX_json_t_to_sv(pTHX_ json_t* json_obj)
#define json_t_to_sv(r) THX_json_t_to_sv(aTHX_ r)
{
    /* TODO: leaks memory on exceptions */
    SV* as_sv = NULL;
    if ( !json_obj ) {
        /* undef */
        return newSV(0);
    }

    switch ( json_typeof(json_obj) ) {
        case JSON_OBJECT:
        {
            HV* hv = newHV();
            void *json_iterator = json_object_iter(json_obj);
            while ( json_iterator ) {
                const char *key = json_object_iter_key(json_iterator); /* no len :( */
                json_t *value   = json_object_iter_value(json_iterator);
                SV *value_sv    = json_t_to_sv(value);

                hv_store(hv, key, strlen(key), value_sv, 0);

                json_iterator   = json_object_iter_next(json_obj, json_iterator);
            }
            as_sv = newRV_noinc(MUTABLE_SV(hv));
            break;
        }
        case JSON_ARRAY:
        {
            AV* av = newAV();
            size_t idx = 0;
            as_sv = newRV_noinc(MUTABLE_SV(av));
            for( idx = 0; idx < json_array_size(json_obj); idx++ ) {
                json_t* inner = json_array_get(json_obj, idx);
                SV * inner_sv = json_t_to_sv(inner);
                av_push(av, inner_sv);
            }
            break;
        }
        case JSON_STRING:
        {
            const char *str = json_string_value(json_obj);
            STRLEN str_len  = json_string_length(json_obj);
            as_sv = newSVpvn_flags(str, str_len, SVf_UTF8);
            break;
        }
        case JSON_INTEGER:
        {
            as_sv = newSViv(json_integer_value(json_obj));
            break;
        }
        case JSON_REAL:
        {
            as_sv = newSViv(json_real_value(json_obj));
            break;
        }
        case JSON_TRUE:
        {
            /* TODO: create a JSON::PP::Boolean object */
            as_sv = newSVsv(&PL_sv_yes);
            break;
        }
        case JSON_FALSE:
        {
            /* TODO: create a JSON::PP::Boolean object */
            as_sv = newSVsv(&PL_sv_no);
            break;
        }
        case JSON_NULL:
        {
            as_sv = newSVsv(&PL_sv_undef);
            break;
        }
        default:
        {
            warn("janssen returned an unknown type ('%d'), no clue how to handle it, will return undef", json_typeof(json_obj));
            as_sv = newSVsv(&PL_sv_undef);
        }
    }

    return as_sv;
}

MODULE = JSON::XS::Jansson  PACKAGE = JSON::XS::Jansson

const char*
jansson_version()
CODE:
{
    RETVAL = jansson_version_str();
}
OUTPUT: RETVAL

SV*
decode_json(SV *json_sv)
CODE:
{
    json_error_t decode_error;
    json_t *json_root          = NULL;
    STRLEN json_len            = 0;
    const char *json_raw       = NULL;

    SvUPGRADE(json_sv, SVt_PV);
    if ( !SvUTF8(json_sv) ) {
        /* janssen only supports UTF-8 strings */
        sv_utf8_upgrade_nomg(json_sv);
    }

    int flags = JSON_REJECT_DUPLICATES | JSON_DECODE_ANY | JSON_ALLOW_NUL | JSON_DISABLE_EOF_CHECK;
    json_raw  = SvPV(json_sv, json_len);
    json_root = json_loadb(json_raw, json_len, flags, &decode_error);

    if ( !json_root ) {
        croak("%s at line %d", decode_error.text, decode_error.line);
    }

    /* todo: ensure we don't leak root here if the function throws an exception */
    RETVAL = json_t_to_sv(json_root);

    json_decref(json_root);
}
OUTPUT: RETVAL

SV*
encode_json(SV *source)
CODE:
{
    json_t *json_root = sv_to_json_t(source, NULL);
    const char *json  = NULL;
    size_t json_len   = 0;

    json_len = json_dumpb(json_root, NULL, 0, 0);

    RETVAL      = newSV(json_len);
    SvUPGRADE(RETVAL, SVt_PV);
    SvPOK_on(RETVAL);

    json_len  = json_dumpb(json_root, SvPVX_mutable(RETVAL), json_len, 0);
    SvCUR_set(RETVAL, json_len);
    json_decref(json_root);
}
OUTPUT: RETVAL

