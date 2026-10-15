#include "expression.h"

#include "lib/code_gen.h"
#include "compiler_util.h"
#include "object.h"
#include "scope.h"

static inline bool object_sameRegister(const Object* a, const Object* b) {
    return a->type == OBJECT_TYPE_REGISTER && b->type == OBJECT_TYPE_REGISTER &&
        a->value.symbol->index == b->value.symbol->index;
}

static inline bool isExpressionOperationLegal(const ExpOp eop, const ObjectType targetType) {
    if (ExpOp_isArithmetic(eop) && !ObjectType_isNumber(targetType)) {
        if (eop == OP_ADD && targetType == OBJECT_TYPE_STR) {
            // String concatenation is legal
        } else {
            yyerrorf("運算符號『%s』不適用於『%s』之屬\n", expOp2str[eop], objectType2str[targetType]);
            return false;
        }
    }
    if (ExpOp_isBooleanOnly(eop) && targetType != OBJECT_TYPE_BOOL) {
        yyerrorf("運算符號『%s』不適用於『%s』之屬\n", expOp2str[eop], objectType2str[targetType]);
        return false;
    }
    if (eop == OP_MOD && !ObjectType_isInteger(targetType)) {
        yyerrorf("運算符號『%s』不適用於『%s』之屬\n", expOp2str[eop], objectType2str[targetType]);
        return false;
    }
    return true;
}

Object code_expression(const ExpOp eop, const bool opLeft, Object* a, Object* b,
                       const YYLTYPE* aLoc, const YYLTYPE* bLoc) {
    ObjectType aValueType = object_getValueType(a), bValueType = object_getValueType(b);

    const ObjectType targetType = object_getPromotedType(aValueType, bValueType);
    if (targetType == OBJECT_TYPE_UNDEFINED) {
        yyerrortf("「%s」與「%s」之屬不可同算\n", aLoc, bLoc, objectType2str[aValueType], objectType2str[bValueType]);
        goto FAILED;
    }
    if (!isExpressionOperationLegal(eop, targetType))
        goto FAILED;

    // Operand direction: opLeft == true means "於" (a is on the right, b is on the left)
    // i.e. result = b <op> a  when opLeft; result = a <op> b otherwise
    Object* left = opLeft ? b : a;
    Object* right = opLeft ? a : b;
    const YYLTYPE* leftLoc = opLeft ? bLoc : aLoc;
    const YYLTYPE* rightLoc = opLeft ? aLoc : bLoc;

    // String concatenation uses runtime call instead of arithmetic IR
    if (eop == OP_ADD && targetType == OBJECT_TYPE_STR) {
        char leftName[MAX_NAME_LENGTH], rightName[MAX_NAME_LENGTH];
        Object regLeft = object_nameLiteralOrLoadReg(left, leftName, MAX_NAME_LENGTH);
        if (regLeft.type == OBJECT_TYPE_UNDEFINED) goto FAILED;
        Object regRight = object_nameLiteralOrLoadReg(right, rightName, MAX_NAME_LENGTH);
        if (regRight.type == OBJECT_TYPE_UNDEFINED) {
            if (left->type == OBJECT_TYPE_SYMBOL) object_free(&regLeft);
            goto FAILED;
        }

        const SymbolData resultReg = object_createRegisterSymbol(OBJECT_TYPE_STR);
        buffPrintln(&ctx->code, "%%reg%s = call ptr @wy_rt_str_concat(ptr %s, ptr %s)",
                    resultReg.name, leftName, rightName);

        if (left->type == OBJECT_TYPE_SYMBOL) object_free(&regLeft);
        if (right->type == OBJECT_TYPE_SYMBOL) object_free(&regRight);

        const Object result = (Object){OBJECT_TYPE_REGISTER, .value.symbol = cloneStruct(SymbolData, &resultReg)};
        compilerLog("exp %s %s %s -> %s\n", object_print(left), opDebugNames[eop], object_print(right),
                    object_print(&result));

        if (!object_sameRegister(a, b)) object_free(a);
        object_free(b);
        return result;
    }

    char leftName[MAX_NAME_LENGTH], rightName[MAX_NAME_LENGTH];
    Object regLeft = object_loadRegAndPromote(left, targetType, leftName, MAX_NAME_LENGTH);
    if (regLeft.type == OBJECT_TYPE_UNDEFINED) goto FAILED;
    Object regRight = object_loadRegAndPromote(right, targetType, rightName, MAX_NAME_LENGTH);
    if (regRight.type == OBJECT_TYPE_UNDEFINED) {
        if (object_getValueType(left) != targetType || left->type == OBJECT_TYPE_SYMBOL) object_free(&regLeft);
        goto FAILED;
    }

    const bool isBoolResult = ExpOp_isOutputLogic(eop);
    const ObjectType resultType = isBoolResult ? OBJECT_TYPE_BOOL : targetType;
    const SymbolData resultReg = object_createRegisterSymbol(resultType);

    const char* opName = ObjectType_isFloat(targetType) ? opIRFloatNames[eop] : opIRIntNames[eop];
    const char* llvmTypeName = objectType2llvmType[targetType];
    buffPrintln(&ctx->code, "%%reg%s = %s %s %s, %s",
                resultReg.name, opName, llvmTypeName, leftName, rightName);

    // Cleanup promoted-or-passthrough operand registers
    if (object_getValueType(left) != targetType || left->type == OBJECT_TYPE_SYMBOL) object_free(&regLeft);
    if (object_getValueType(right) != targetType || right->type == OBJECT_TYPE_SYMBOL) object_free(&regRight);

    const Object result = (Object){OBJECT_TYPE_REGISTER, .value.symbol = cloneStruct(SymbolData, &resultReg)};
    compilerLog("exp %s %s %s -> %s\n", object_print(left), opDebugNames[eop], object_print(right),
                object_print(&result));

    if (!object_sameRegister(a, b)) object_free(a);
    object_free(b);
    return result;

FAILED:
    if (!object_sameRegister(a, b)) object_free(a);
    object_free(b);
    return (Object){.type = OBJECT_TYPE_UNDEFINED, .value = {}};
}

Object code_expressionMod(ExpOp dop, ExpOp eop, bool op_left, Object* a, Object* b,
                          YYLTYPE* dopLoc, YYLTYPE* eopLoc) {
    if (dop != OP_DIV) {
        yyerrorf("欲問所餘，必先用除\n");
        goto FAILED;
    }
    return code_expression(eop, op_left, a, b, dopLoc, eopLoc);

FAILED:
    if (!object_sameRegister(a, b)) object_free(a);
    object_free(b);
    return (Object){.type = OBJECT_TYPE_UNDEFINED, .value = {}};
}

Object code_expressionChain(ExpOp eop, bool op_left, Object* a, Object* b,
                            YYLTYPE* aLoc, YYLTYPE* bLoc) {
    return code_expression(eop, op_left, a, b, aLoc, bLoc);
}

Object code_expressionChainMod(ExpOp dop, ExpOp eop, bool op_left, Object* a, Object* b,
                               YYLTYPE* dopLoc, YYLTYPE* eopLoc) {
    if (dop != OP_DIV) {
        yyerrorf("欲問所餘，必先用除\n");
        object_free(a);
        object_free(b);
        return (Object){.type = OBJECT_TYPE_UNDEFINED, .value = {}};
    }
    return code_expressionChain(eop, op_left, a, b, dopLoc, eopLoc);
}
