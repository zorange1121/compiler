//
// Created by WavJaby on 2026/3/2.
//

#include "value_data.h"

#include <string.h>

#include "compiler_util.h"

// linkedList_init / linkedList_addp / linkedList_deleteNode / linkedList_freeA / cloneStruct 用法：見 README.md §工具函式速查
bool object_ValueDataListCreate(ObjectType valueType, const ScientificNotation* count, ValueData* valueData) {
    linkedList_init(&valueData->valueList);
    valueData->valueType = valueType;
    valueData->count = (count != NULL) ? sciToInt32(count) : 1;
    if (valueData->count <= 0) {
        yyerrorf("立名之數，當為正數，不可為「%d」\n", valueData->count);
        return true;
    }
    return false;
}

bool object_ValueDataListAdd(ValueData* valueData, const Object* obj, const YYLTYPE* tokenLoc) {
    if ((int32_t)valueData->valueList.length >= valueData->count) {
        yyerrorlf("所列之值，多於所宣之數\n", tokenLoc);
        return true;
    }

    const ObjectType objValueType = object_getValueType(obj);
    if (valueData->valueType == OBJECT_TYPE_AUTO) {
        valueData->valueType = objValueType;
    } else if (valueData->valueType != OBJECT_TYPE_STR && valueData->valueType != objValueType &&
               object_getPromotedType(valueData->valueType, objValueType) == OBJECT_TYPE_UNDEFINED) {
        // STR-typed lists ("言") are also used for heterogeneous print statements
        // (e.g. 吾有四言。曰"text"。曰「numVar」), so don't enforce strict typing there.
        yyerrorlf("所列之值，其類「%s」與所宣之類「%s」不符\n", tokenLoc,
                  objectType2str[objValueType], objectType2str[valueData->valueType]);
        return true;
    }

    Object* clone = cloneStruct(Object, obj);
    if (obj->type == OBJECT_TYPE_STR && obj->value.str)
        clone->value.str = strdup(obj->value.str);
    else if ((obj->type == OBJECT_TYPE_I32 || obj->type == OBJECT_TYPE_I64 ||
              obj->type == OBJECT_TYPE_F64 || obj->type == OBJECT_TYPE_NUM) && obj->value.number)
        clone->value.number = cloneStruct(ScientificNotation, obj->value.number);
    else if (obj->type == OBJECT_TYPE_REGISTER && obj->value.symbol)
        clone->value.symbol = symbol_clone(obj->value.symbol);
    linkedList_addp(&valueData->valueList, 0, clone); // freeFlag=0：不自動 free，由 freeA(free) 統一釋放
    return false;
}

bool object_ValueDataListAddDefaults(ValueData* valueData, const YYLTYPE* tokenLoc) {
    const int32_t missing = valueData->count - (int32_t)valueData->valueList.length;
    for (int32_t i = 0; i < missing; i++) {
        Object defaultObj;
        switch (valueData->valueType) {
        case OBJECT_TYPE_BOOL:
            defaultObj = object_createBool(false);
            break;
        case OBJECT_TYPE_STR:
            defaultObj = object_createStrConst("");
            break;
        case OBJECT_TYPE_ARRAY:
            defaultObj = object_createArray();
            break;
        case OBJECT_TYPE_NUM:
        case OBJECT_TYPE_I32:
        case OBJECT_TYPE_I64:
        case OBJECT_TYPE_F64: {
            const ScientificNotation zero = {.type = I32, .fraction = 0, .fractionLen = 1, .exp = 0};
            defaultObj = object_createNumber(&zero);
            break;
        }
        default:
            yyerrorlf("莫識其類『%s』，無由補其值\n", tokenLoc, objectType2str[valueData->valueType]);
            return true;
        }
        if (object_ValueDataListAdd(valueData, &defaultObj, tokenLoc)) {
            object_free(&defaultObj);
            return true;
        }
        object_free(&defaultObj);
    }
    return false;
}

Object* object_ValueDataListPop(ValueData* valueData) {
    if (valueData->valueList.length == 0)
        return NULL;
    LinkedListNode* node = valueData->valueList.head->next;
    Object* obj = node->value;
    linkedList_deleteNode(&valueData->valueList, node);
    return obj;
}

bool object_ValueDataListFree(ValueData* valueData) {
    linkedList_freeA(&valueData->valueList, free);
    return false;
}
