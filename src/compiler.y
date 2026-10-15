/* Definition section */
%code requires {
    # define YYLTYPE_IS_DECLARED 1
    # define YYLTYPE_IS_TRIVIAL 1
}

%{
    #include "compiler_util.h"
    #include "main.h"
    #include "expression.h"
    #include "value_data.h"
    #include "scope.h"
    #include "control/for.h"
    #include "control/if.h"
    #include "control/while.h"
    #include "control/function.h"
%}

%define parse.error custom
%locations

/* Variable or self-defined structure */
%union {
    ObjectType var_type;

    bool b_var;
    ScientificNotation n_var;
    char *s_var;

    Object obj_val;
    ValueData val_data;

    FuncCallInfo* func_call;

    bool exp_left;
    ExpOp exp_op;
}
/* Token */
%token COMMENT
%token HERE_ARE HERE_IS_A SAID NAME_IT
%token PRINT TO_CALL CALL
%token RETURN
%token IS_THUS PAST SET ITS TOPIC
%token IF ELSE_IF ELSE
%token WHILE_TRUE FOR TIMES BREAK END
%token TO_PERFORM_FUNC REQUIRE_ARGS FUNC_BEGIN FUNC_END_FOR FUNC_END
%token THOSE PUSH TAKE LENGTH INDEX

%token <n_var> NUMBER_LIT
%token <b_var> BOOL_LIT
%token <var_type> VAR_TYPE VAR_TYPE_FUNC
%token <s_var> STR_LIT IDENT
%token <exp_op> EXP_MATH_OP EXP_MATH_MOD_OP EXP_LOGIC_OP
%token <exp_left> EXP_PREPOSITION

/* %left 範例 — ValueStmt 實作時視衝突補充 */
%left INDEX

/* Nonterminal with return */
%type <val_data> CreateValueDataListStmt ValueAccumList ValueListTail
%type <obj_val> ValueLiteralStmt VariableStmt LitOrVarStmt
%type <obj_val> ValueStmt ValueLiteralOrLastStmt
%type <obj_val> ExpressionStmt ExpressionChainStmt ExpressionNextStmt
%type <obj_val> FunctionCallStmt
%type <exp_op> ModSuffixOpt

/* For Return — 用於已提供的 ReturnStmt，詳見 YACC_CHEATSHEET.md §優先序宣告 */
%nonassoc LOWER_THAN_EXPR
%nonassoc RETURN

/* Yacc will start at this nonterminal */
%start Program
%%
/* Grammar section */

/* Scope */
Program
    : GlobalScopeStmt
;

GlobalScopeStmt
    : BodyListStmt
;

/* Scope Body */
BodyListStmt
    : BodyListStmt BodyStmt
    |
;

BodyStmt
    : COMMENT STR_LIT
    | OperationStmt
    | ConditionStmt
    | FunctionStmt
;

/* Function */
FunctionStmt
    : HERE_ARE NUMBER_LIT VAR_TYPE_FUNC NAME_IT IDENT
        {
            if (($<obj_val>$ = func_define(&$<n_var>2, $<s_var>5)).type == OBJECT_TYPE_UNDEFINED)
                YYABORT;
        }
      FunctionArgsStmt FUNC_BEGIN
        {
            if (func_defineBody()) YYABORT;
        }
      BodyListStmt FUNC_END_FOR IDENT FUNC_END
        {
            char* funcName = $<s_var>12;
            if (func_defineBodyEnd(&$<obj_val>6, funcName)) {
                free(funcName);
                YYABORT;
            }
            free(funcName);
        }
;

FunctionArgsStmt
    : TO_PERFORM_FUNC REQUIRE_ARGS NUMBER_LIT VAR_TYPE FunctionArgListStmt
    | /* no args */
;

FunctionArgListStmt
    : SAID IDENT
        {
            if (func_defineAddParam($<var_type>0, $<s_var>2)) YYABORT;
        }
    | FunctionArgListStmt SAID IDENT
        {
            if (func_defineAddParam($<var_type>0, $<s_var>3)) YYABORT;
        }
;

/* Condition and Operation */
ConditionStmt
    : WHILE_TRUE
        {
            if (code_whileLoopStart()) YYABORT;
        }
      BodyListStmt END
        {
            if (code_whileLoopEnd(NULL)) YYABORT;
        }
    | FOR NUMBER_LIT TIMES
        {
            Object cnt = object_createNumber(&$<n_var>2);
            if (code_forLoop(&cnt)) YYABORT;
        }
      BodyListStmt END
        {
            if (code_forLoopEnd(NULL)) YYABORT;
        }
    | FOR VariableStmt TIMES
        {
            if (code_forLoop(&$<obj_val>2)) YYABORT;
        }
      BodyListStmt END
        {
            if (code_forLoopEnd(NULL)) YYABORT;
        }
    | IF ExpressionChainStmt TOPIC
        {
            if (code_if(&$<obj_val>2)) YYABORT;
        }
      BodyListStmt IfElseStmt
        {
            if (code_ifEnd()) YYABORT;
        }
;

IfElseStmt
    : END
    | ElseIfList END
    | ElseIfList ElseStmt END
    | ElseStmt END
;

ElseIfList
    : ElseIfOne
    | ElseIfList ElseIfOne
;

ElseIfOne
    : ELSE_IF
        {
            if (code_elseIfLabel()) YYABORT;
        }
      ExpressionChainStmt TOPIC
        {
            if (code_elseIf(&$<obj_val>3)) YYABORT;
        }
      BodyListStmt
;

ElseStmt
    : ELSE
        {
            if (code_else()) YYABORT;
        }
      BodyListStmt
;

/* Operation statements: declare/name, assign, print, push, break, return, bare expr/call */
OperationStmt
    : CreateValueDataListStmt ValueAccumList
        {
            ValueData* vd = &$<val_data>2;
            if (vd->valueList.length == 0 && object_ValueDataListAddDefaults(vd, &@2)) YYABORT;
            $<val_data>$ = *vd;
        }
      VariableDefineStmt
        {
            object_ValueDataListFree(&$<val_data>3);
        }
    | CreateValueDataListStmt ValueAccumList PRINT
        {
            ValueData* vd = &$<val_data>2;
            if (code_stdoutPrint(vd, true)) YYABORT;
            object_ValueDataListFree(vd);
        }
    | PAST VariableStmt TOPIC SET VariableStmt IS_THUS
        {
            if (code_assign(&$<obj_val>2, &$<obj_val>5)) YYABORT;
        }
    | PAST VariableStmt TOPIC SET ITS IS_THUS
        {
            Object srcObj = ctx->last_result;
            ctx->last_result = (Object){.type = OBJECT_TYPE_UNDEFINED};
            // "其" has no source token of its own worth reporting; point the
            // log at the destination variable (@2) instead.
            yylloc = @2;
            if (code_assign(&$<obj_val>2, &srcObj)) YYABORT;
        }
    | PAST VariableStmt TOPIC SET ExpressionChainStmt IS_THUS
        {
            if (code_assign(&$<obj_val>2, &$<obj_val>5)) YYABORT;
        }
    | PUSH VariableStmt
        {
            $<obj_val>$ = $<obj_val>2;
        }
      PushItemList
    | BREAK
        {
            if (code_break()) YYABORT;
        }
    | RETURN
        {
            // Bare "乃得矣" implicitly returns the most recently computed value (其),
            // matching the language's general "其" convention; truly nothing computed
            // yet means a real void return.
            const YYLTYPE savedLoc = yylloc;
            yylloc = @1;
            if (ctx->last_result.type != OBJECT_TYPE_UNDEFINED) {
                Object retObj = ctx->last_result;
                ctx->last_result = (Object){.type = OBJECT_TYPE_UNDEFINED};
                // Do not object_free(&retObj) here: code_return's internal
                // object_loadRegAndPromote often passes through the same
                // REGISTER/NUMBER pointer (no type promotion needed), and
                // code_return already frees that pointer itself.
                if (code_return(&retObj)) YYABORT;
            } else {
                Object voidObj = {.type = OBJECT_TYPE_UNDEFINED};
                if (code_return(&voidObj)) YYABORT;
            }
            yylloc = savedLoc;
        }
    | RETURN ExpressionChainStmt %prec LOWER_THAN_EXPR
        {
            Object retObj = $<obj_val>2;
            // See note above: code_return may already free retObj's underlying
            // pointer via a REGISTER/NUMBER passthrough, so don't double-free here.
            if (code_return(&retObj)) YYABORT;
        }
    | CreateValueDataListStmt ValueAccumList TAKE NUMBER_LIT TO_CALL VariableStmt
        {
            ValueData* vd = &$<val_data>2;
            Object funcObj = $<obj_val>6;
            {
                const YYLTYPE savedLoc = yylloc;
                yylloc = @6;
                if (func_takeAndCall(&$<n_var>4, &funcObj, vd, &@4)) YYABORT;
                yylloc = savedLoc;
            }
            Object* ret = object_ValueDataListPop(vd);
            ctx->last_result = ret ? *ret : (Object){.type = OBJECT_TYPE_UNDEFINED};
            free(ret);
            object_ValueDataListFree(vd);
            object_free(&funcObj);
        }
    | ExpressionChainStmt TAKE NUMBER_LIT TO_CALL VariableStmt NAME_IT IDENT
        {
            ValueData vd;
            const ObjectType t = object_getValueType(&$<obj_val>1);
            if (object_ValueDataListCreate(t, NULL, &vd)) YYABORT;
            if (object_ValueDataListAdd(&vd, &$<obj_val>1, &@1)) YYABORT;
            Object funcObj = $<obj_val>5;
            {
                const YYLTYPE savedLoc = yylloc;
                yylloc = @5;
                if (func_takeAndCall(&$<n_var>3, &funcObj, &vd, &@3)) YYABORT;
                yylloc = savedLoc;
            }
            if (code_createVariable(&vd, $<s_var>7)) YYABORT;
            object_free(&funcObj);
        }
    | ExpressionChainStmt NAME_IT IDENT
        {
            ValueData vd;
            const ObjectType expType = object_getValueType(&$<obj_val>1);
            if (object_ValueDataListCreate(expType, NULL, &vd)) YYABORT;
            if (object_ValueDataListAdd(&vd, &$<obj_val>1, &@1)) YYABORT;
            if (code_createVariable(&vd, $<s_var>3)) YYABORT;
            object_ValueDataListFree(&vd);
        }
    | ExpressionChainStmt PRINT
        {
            ValueData vd;
            const ObjectType expType = object_getValueType(&$<obj_val>1);
            if (object_ValueDataListCreate(expType, NULL, &vd)) YYABORT;
            if (object_ValueDataListAdd(&vd, &$<obj_val>1, &@1)) YYABORT;
            if (code_stdoutPrint(&vd, true)) YYABORT;
            object_ValueDataListFree(&vd);
        }
    | ExpressionChainStmt
        {
            // Ownership transferred to ctx->last_result; do not free here (it would
            // dangle the pointer for the eventual `其`/ITS consumer).
            ctx->last_result = $<obj_val>1;
        }
;

ValueAccumList
    : /* empty */
        {
            $$ = $<val_data>0;
        }
    | LitOrVarStmt
        {
            $<val_data>$ = $<val_data>0;
            if (object_ValueDataListAdd(&$<val_data>$, &$<obj_val>1, &@1)) YYABORT;
        }
      ValueListTail
        {
            $$ = $<val_data>3;
        }
    | ValueLiteralStmt
        {
            $<val_data>$ = $<val_data>0;
            if (object_ValueDataListAdd(&$<val_data>$, &$<obj_val>1, &@1)) YYABORT;
        }
;

ValueListTail
    : /* empty */
        {
            $$ = $<val_data>0;
        }
    | ValueListTail LitOrVarStmt
        {
            $<val_data>$ = $<val_data>1;
            if (object_ValueDataListAdd(&$<val_data>$, &$<obj_val>2, &@2)) YYABORT;
        }
;

PushItemList
    : EXP_PREPOSITION ValueLiteralOrLastStmt
        {
            if (code_arrayPush(&$<obj_val>0, &$<obj_val>2, &@2)) YYABORT;
        }
    | PushItemList EXP_PREPOSITION ValueLiteralOrLastStmt
        {
            if (code_arrayPush(&$<obj_val>0, &$<obj_val>3, &@3)) YYABORT;
        }
;

CreateValueDataListStmt
    : HERE_IS_A VAR_TYPE
        {
            if (object_ValueDataListCreate($<var_type>2, NULL, &$$)) YYABORT;
        }
    | HERE_ARE NUMBER_LIT VAR_TYPE
        {
            if (object_ValueDataListCreate($<var_type>3, &$<n_var>2, &$$)) YYABORT;
        }
;

VariableDefineStmt
    : NAME_IT IDENT
        {
            if (code_createVariable(&$<val_data>0, $<s_var>2)) YYABORT;
        }
    | VariableDefineStmt SAID IDENT
        {
            if (code_createVariable(&$<val_data>0, $<s_var>3)) YYABORT;
        }
;

/* Expressions */
ExpressionChainStmt
    : ExpressionStmt
        {
            $$ = $1;
            ctx->last_result = $$;
        }
    | ExpressionChainStmt ExpressionNextStmt
        {
            $$ = $2;
            ctx->last_result = $$;
        }
;

ExpressionStmt
    : EXP_MATH_OP ValueStmt EXP_PREPOSITION ValueLiteralOrLastStmt ModSuffixOpt
        {
            if ($<exp_op>5 == OP_MOD)
                $$ = code_expressionMod($<exp_op>1, OP_MOD, $<exp_left>3, &$<obj_val>2, &$<obj_val>4, &@2, &@4);
            else
                $$ = code_expression($<exp_op>1, $<exp_left>3, &$<obj_val>2, &$<obj_val>4, &@2, &@4);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | ValueStmt EXP_LOGIC_OP ValueLiteralOrLastStmt ModSuffixOpt
        {
            $$ = code_expression($<exp_op>2, false, &$<obj_val>1, &$<obj_val>3, &@1, &@3);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | THOSE ValueStmt ValueStmt EXP_LOGIC_OP
        {
            $$ = code_expression($<exp_op>4, false, &$<obj_val>2, &$<obj_val>3, &@2, &@3);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | FunctionCallStmt
        {
            $$ = $1;
        }
    | ValueStmt %prec LOWER_THAN_EXPR
        {
            $$ = $1;
        }
;

ExpressionNextStmt
    : EXP_MATH_OP ValueLiteralOrLastStmt EXP_PREPOSITION ValueLiteralOrLastStmt ModSuffixOpt
        {
            Object left = $<obj_val>2;
            if ($<exp_op>5 == OP_MOD)
                $$ = code_expressionChainMod($<exp_op>1, OP_MOD, $<exp_left>3, &left, &$<obj_val>4, &@2, &@4);
            else
                $$ = code_expressionChain($<exp_op>1, $<exp_left>3, &left, &$<obj_val>4, &@2, &@4);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | EXP_MATH_OP ValueStmt EXP_MATH_MOD_OP TOPIC EXP_PREPOSITION ValueLiteralOrLastStmt
        {
            $$ = code_expressionChainMod($<exp_op>1, $<exp_op>3, $<exp_left>5, &$<obj_val>2, &$<obj_val>6, &@2, &@6);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
;

ValueLiteralOrLastStmt
    : ValueStmt { $$ = $1; }
    | ITS { $$ = ctx->last_result; ctx->last_result = (Object){.type = OBJECT_TYPE_UNDEFINED}; }
;

ModSuffixOpt
    : /* empty */ { $$ = OP_ADD; }
    | EXP_MATH_MOD_OP { $$ = $1; }
;

/* Value */
ValueStmt
    : LitOrVarStmt
        {
            $$ = $1;
        }
    | ValueLiteralStmt
        {
            $$ = $1;
        }
    | VariableStmt
        {
            $$ = $1;
        }
    | THOSE VariableStmt INDEX ValueStmt
        {
            $$ = object_getIndex(&$<obj_val>2, &$<obj_val>4, &@2, &@4);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | THOSE VariableStmt LENGTH
        {
            $$ = code_getLength(&$<obj_val>2, &@2);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | VariableStmt INDEX ValueStmt
        {
            $$ = object_getIndex(&$<obj_val>1, &$<obj_val>3, &@1, &@3);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | VariableStmt LENGTH
        {
            $$ = code_getLength(&$<obj_val>1, &@1);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | THOSE VariableStmt
        {
            $$ = $2;
        }
;

LitOrVarStmt
    : SAID ValueLiteralStmt
        {
            $$ = $2;
        }
    | SAID VariableStmt
        {
            $$ = $2;
        }
    | SAID ExpressionChainStmt %prec LOWER_THAN_EXPR
        {
            $$ = $2;
        }
;

ValueLiteralStmt
    : NUMBER_LIT
        {
            $$ = object_createNumber(&$<n_var>1);
            if ($$.type == OBJECT_TYPE_UNDEFINED) YYABORT;
        }
    | BOOL_LIT
        {
            $$ = object_createBool($<b_var>1);
        }
    | STR_LIT
        {
            $$ = object_createStr($<s_var>1);
        }
;

VariableStmt
    : IDENT
        {
            if (($$ = scope_findSymbol($<s_var>1)).type == OBJECT_TYPE_UNDEFINED) YYABORT;
            free($<s_var>1);
        }
;

/* Function call: prefix CALL「name」於arg1於arg2... and postfix TAKE n TO_CALL「name」 */
FunctionCallStmt
    : CALL VariableStmt
        {
            $<func_call>$ = func_callInit(&$<obj_val>2);
            if (!$<func_call>$) YYABORT;
        }
      FuncCallArgList
        {
            ValueData funcReturn = {0};
            func_call($<func_call>3, &$<obj_val>2, &funcReturn, &@1);
            Object* ret = object_ValueDataListPop(&funcReturn);
            if (ret) {
                $$ = *ret;
                free(ret);
            } else {
                $$ = (Object){.type = OBJECT_TYPE_UNDEFINED};
            }
            object_ValueDataListFree(&funcReturn);
            object_free(&$<obj_val>2);
        }
;
/* Postfix TAKE n TO_CALL「name」is handled directly in OperationStmt (the value(s)
   it takes from only make sense relative to a preceding ValueAccumList or expression
   chain, neither of which is reachable from this non-terminal's own $0). */

FuncCallArgList
    : EXP_PREPOSITION ValueLiteralOrLastStmt
        {
            if (func_callArgAdd($<func_call>0, &$<obj_val>2, &@2)) YYABORT;
        }
    | FuncCallArgList EXP_PREPOSITION ValueLiteralOrLastStmt
        {
            if (func_callArgAdd($<func_call>0, &$<obj_val>3, &@3)) YYABORT;
        }
;

%%

#include "compiler.h"
