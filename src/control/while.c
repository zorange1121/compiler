//
// Created by Wavjaby on 2026/3/27.
//

#include "while.h"

#include <WJCL/string/wjcl_string.h>

#include "lib/code_gen.h"
#include "../compiler_util.h"

bool code_whileLoopStart() {
    compilerLog("> (while loop)\n");

    const ScopeData* scope = scope_pushType(SCOPE_WHILE_LOOP);

    buffPrintln(&ctx->code, "");
    buffPrintln(&ctx->code, "br label %%loop%d.body", scope->id);
    buffPrintlnS(&ctx->code, "loop%d.body:", scope->id);

    return false;
}

bool code_whileLoopEnd(Object* obj) {
    const ScopeData* scope = scope_peek();

    buffPrintln(&ctx->code, "br label %%loop%d.body", scope->id);
    buffPrintlnS(&ctx->code, "loop%d.exit:", scope->id);
    buffPrintln(&ctx->code, "");

    scope_dump();
    compilerLog("< (while loop end)\n");
    return false;
}

bool code_break() {
    const ScopeData* loopScope = scope_findNearestLoop();
    if (!loopScope) {
        yyerrorf("乃止當施於迴圈之內，不可在外\n");
        return true;
    }

    compilerLog("break (loop%d)\n", loopScope->id);
    buffPrintln(&ctx->code, "br label %%loop%d.exit", loopScope->id);
    return false;
}
