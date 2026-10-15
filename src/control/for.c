//
// Created by WavJaby on 2026/03/26.
//

#include "for.h"

#include <WJCL/string/wjcl_string.h>

#include "lib/code_gen.h"
#include "compiler_util.h"

bool code_forLoop(Object* src) {
    if (src->type == OBJECT_TYPE_UNDEFINED)
        goto FAILED;

    compilerLog("> (for loop, count: %s)\n", object_print(src));

    {
        char countName[MAX_NAME_LENGTH];
        Object regCount = object_loadRegAndPromote(src, OBJECT_TYPE_I32, countName, MAX_NAME_LENGTH);
        if (regCount.type == OBJECT_TYPE_UNDEFINED) goto FAILED;

        ScopeData* scope = scope_pushType(SCOPE_FOR_LOOP);
        scope->u.forLoop.symbol = (SymbolData){.type = OBJECT_TYPE_I32, .name = strdup("i"), .index = scope->id};
        const char* typeName = objectType2llvmType[scope->u.forLoop.symbol.type];

        buffPrintln(&ctx->code, "");
        buffPrintln(&ctx->code, "br label %%loop%d.entry", scope->id);
        buffPrintlnS(&ctx->code, "loop%d.entry:", scope->id);
        buffPrintln(&ctx->code, "br label %%loop%d.header", scope->id);
        buffPrintlnS(&ctx->code, "loop%d.header:", scope->id);
        buffPrintln(&ctx->code, "%%loop%d.i = phi %s [ 0, %%loop%d.entry ], [ %%loop%d.i.next, %%loop%d.update ]",
                    scope->id, typeName, scope->id, scope->id, scope->id);
        buffPrintln(&ctx->code, "%%loop%d.cond = icmp slt %s %%loop%d.i, %s",
                    scope->id, typeName, scope->id, countName);
        buffPrintln(&ctx->code, "br i1 %%loop%d.cond, label %%loop%d.body, label %%loop%d.exit",
                    scope->id, scope->id, scope->id);
        buffPrintlnS(&ctx->code, "loop%d.body:", scope->id);

        if (src->type == OBJECT_TYPE_SYMBOL) object_free(&regCount);
    }

    object_free(src);
    return false;
FAILED:
    object_free(src);
    return true;
}

bool code_forLoopEnd(Object* obj) {
    const ScopeData* scope = scope_peek();
    const char* typeName = objectType2llvmType[scope->u.forLoop.symbol.type];

    buffPrintln(&ctx->code, "br label %%loop%d.update", scope->id);
    buffPrintlnS(&ctx->code, "loop%d.update:", scope->id);
    buffPrintln(&ctx->code, "%%loop%d.i.next = add nsw %s %%loop%d.i, 1", scope->id, typeName, scope->id);
    buffPrintln(&ctx->code, "br label %%loop%d.header", scope->id);
    buffPrintlnS(&ctx->code, "loop%d.exit:", scope->id);
    buffPrintln(&ctx->code, "");

    free(scope->u.forLoop.symbol.name);
    scope_dump();
    compilerLog("< (for loop end)\n");
    return false;
}
