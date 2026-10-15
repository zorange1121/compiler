//
// Created by Wavjaby on 2026/3/26.
//

#include "if.h"

#include <WJCL/string/wjcl_string.h>

#include "lib/code_gen.h"
#include "compiler_util.h"

inline bool code_if(Object* src) {
    compilerLog("> (if)\n");

    char condName[MAX_NAME_LENGTH];
    Object regCond = object_loadRegAndPromote(src, OBJECT_TYPE_BOOL, condName, MAX_NAME_LENGTH);
    if (regCond.type == OBJECT_TYPE_UNDEFINED) {
        object_free(src);
        return true;
    }

    const ScopeData* scope = scope_pushType(SCOPE_IF_STMT);
    ((ScopeData*)scope)->u.ifInfo = (IfInfo){.elseifCount = 0, .containsElse = false};

    buffPrintln(&ctx->code, "br i1 %s, label %%if%d.true, label %%if%d.false", condName, scope->id, scope->id);
    buffPrintlnS(&ctx->code, "if%d.true:", scope->id);

    if (object_getValueType(src) != OBJECT_TYPE_BOOL || src->type == OBJECT_TYPE_SYMBOL) object_free(&regCond);
    object_free(src);
    return false;
}

inline bool code_elseIfLabel() {
    ScopeData* scope = scope_peek();
    const int scopeId = scope->id;
    const int elseifCount = scope->u.ifInfo.elseifCount;

    buffPrintln(&ctx->code, "br label %%if%d.endif", scopeId);
    if (elseifCount == 0)
        buffPrintlnS(&ctx->code, "if%d.false:", scopeId);
    else
        buffPrintlnS(&ctx->code, "if%d.elseif%d.false:", scopeId, elseifCount - 1);

    return false;
}

inline bool code_elseIf(Object* src) {
    ScopeData* oldScope = scope_peek();
    const int scopeId = oldScope->id;
    const int elseifCount = oldScope->u.ifInfo.elseifCount;
    scope_dump();

    compilerLog("> (else if)\n");

    char condName[MAX_NAME_LENGTH];
    Object regCond = object_loadRegAndPromote(src, OBJECT_TYPE_BOOL, condName, MAX_NAME_LENGTH);
    if (regCond.type == OBJECT_TYPE_UNDEFINED) {
        object_free(src);
        return true;
    }

    ScopeData* scope = scope_pushId(SCOPE_IF_STMT, scopeId);
    scope->u.ifInfo = (IfInfo){.elseifCount = elseifCount + 1, .containsElse = false};

    buffPrintln(&ctx->code, "br i1 %s, label %%if%d.elseif%d.true, label %%if%d.elseif%d.false",
                condName, scopeId, elseifCount, scopeId, elseifCount);
    buffPrintlnS(&ctx->code, "if%d.elseif%d.true:", scopeId, elseifCount);

    if (object_getValueType(src) != OBJECT_TYPE_BOOL || src->type == OBJECT_TYPE_SYMBOL) object_free(&regCond);
    object_free(src);
    return false;
}

inline bool code_else() {
    ScopeData* oldScope = scope_peek();
    const int scopeId = oldScope->id;
    const int elseifCount = oldScope->u.ifInfo.elseifCount;
    scope_dump();

    compilerLog("> (else)\n");

    buffPrintln(&ctx->code, "br label %%if%d.endif", scopeId);
    if (elseifCount == 0)
        buffPrintlnS(&ctx->code, "if%d.false:", scopeId);
    else
        buffPrintlnS(&ctx->code, "if%d.elseif%d.false:", scopeId, elseifCount - 1);

    ScopeData* scope = scope_pushId(SCOPE_IF_STMT, scopeId);
    scope->u.ifInfo = (IfInfo){.elseifCount = elseifCount, .containsElse = true};

    return false;
}

inline bool code_ifEnd() {
    ScopeData* scope = scope_peek();
    const int scopeId = scope->id;
    const int elseifCount = scope->u.ifInfo.elseifCount;
    const bool containsElse = scope->u.ifInfo.containsElse;

    if (containsElse) {
        buffPrintln(&ctx->code, "br label %%if%d.endif", scopeId);
        buffPrintlnS(&ctx->code, "if%d.endif:", scopeId);
    } else if (elseifCount == 0) {
        buffPrintln(&ctx->code, "br label %%if%d.false", scopeId);
        buffPrintlnS(&ctx->code, "if%d.false:", scopeId);
    } else {
        buffPrintln(&ctx->code, "br label %%if%d.endif", scopeId);
        buffPrintlnS(&ctx->code, "if%d.elseif%d.false:", scopeId, elseifCount - 1);
        buffPrintlnS(&ctx->code, "if%d.endif:", scopeId);
    }

    scope_dump();
    compilerLog("< (if end)\n");
    return false;
}
