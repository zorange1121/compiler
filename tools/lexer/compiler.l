/* Definition section */
%option yymore 
%{
    #include <utf8.c/utf8.h>
    #include "chinese_number.h"
    #include "compiler_util.h"

    #define YY_NO_UNPUT
    #define YY_NO_INPUT

    int yycolumnUtf8 = 0;
    int yylengUtf8, yytokenLine = 1;
    int startLine, startCol;
    char bom_cache[4] = "";
    utf8_string yytextUtf8;

    static inline void updateNewline() {
        yytokenLine++;
        yycolumnUtf8 = 0;
    }

    /* Calculates UTF-8 character length to update the column counters */
    static inline void processUtf8Char() {
        yytextUtf8 = make_utf8_string(yytext);
        if (yytextUtf8.str) {
            // TODO: Calculate the column number
            yylengUtf8 = utf8_char_count(yytextUtf8);
            yycolumnUtf8 += yylengUtf8;
        }
    }

    /* Appends the next matched token and reverting the column counters to the start of the string */
    static inline void yymore_utf8() {
        yymore();
        if (yytextUtf8.str) {
           yycolumnUtf8 -= yylengUtf8; 
        }
    }

    #define YY_USER_ACTION \
        processUtf8Char();

    #define PRINT_TOKEN(format, ...) do { \
        printf("%s%d:%d: " format "\n", bom_cache, yytokenLine, yycolumnUtf8 - yylengUtf8 + 1, __VA_ARGS__); \
        bom_cache[0] = '\0'; /* 印過一次就清空，免得後面的 Token 被污染 */ \
    } while(0)

    /* Extracts string from the current token by specified padding */
    char* trimStringToken(int paddLen) {
        static char cache[1024];
        int len = strlen(yytext);
        int targetLen = len - (paddLen * 2);
        if (targetLen > 0) {
            strncpy(cache, yytext + paddLen, targetLen);
            cache[targetLen] = '\0';          
        } else {
            cache[0] = '\0';                
        }
        return cache;
    }
%}

/* Define regular expression label */
digit ("零"|"一"|"二"|"三"|"四"|"五"|"六"|"七"|"八"|"九"|"十"|"百"|"千"|"萬"|"兩"|"·")
UTF8_BOM "\357\273\277"

ASCII   [\x00-\x7f]
U       [\x80-\xbf]

B2      [\xC2-\xDF]{U}
B3_1    \xE0[\xA0-\xBF]{U}
B3_2    [\xE1-\xEC]{U}{U}
B3_3    \xED[\x80-\x9F]{U}
B3_4    [\xEE-\xEF]{U}{U}
B4_1    \xF0[\x90-\xBF]{U}{U}
B4_2    [\xF1-\xF3]{U}{U}{U}
B4_3    \xF4[\x80-\x8F]{U}{U}

/* ALL UTF-8 https://www.w3.org/2005/03/23-lex-U#charRange
  {ASCII}
| ([\xC2-\xDF] {U})
| ( \xE0       [\xA0-\xBF]{U})
| ([\xE1-\xEC] {U}{U})
| ( \xED       [\x80-\x9F]{U})
| ([\xEE-\xEF] {U}{U})
| ( \xF0       [\x90-\xBF]{U}{U})
| ([\xF1-\xF3] {U}{U}{U})
| ( \xF4       [\x80-\x8F]{U}{U})
*/

ALL_UTF8 {ASCII}|{B2}|{B3_1}|{B3_2}|{B3_3}|{B3_4}|{B4_1}|{B4_2}|{B4_3}

B3_2_EXCLUDE_QUO ([\xE1-\xE2]{U}{U})|(\xE3\x80[\x80-\x8C\x8E-\xBF])|(\xE3[\x81-\xBF]{U})|([\xE4-\xEC]{U}{U})

EXCLUDE_QUO [\x20-\x7E]|{B2}|{B3_1}|{B3_2_EXCLUDE_QUO}|{B3_3}|{B3_4}|{B4_1}|{B4_2}|{B4_3}
%option yylineno
%x IDENT_CON
%x STRING_COMMENT


 /* Rules section */
%%

"「"        { BEGIN(IDENT_CON); yymore_utf8(); }
<IDENT_CON>"」"    { BEGIN(INITIAL); PRINT_TOKEN("IDENT '%s'", trimStringToken(3)); }
<IDENT_CON>\r?\n    { yymore_utf8(); }
<IDENT_CON>{EXCLUDE_QUO}+    { yymore_utf8(); }


"注曰"|"疏曰"|"批曰"    {
    PRINT_TOKEN("COMMENT %s", yytext);
    //BEGIN(STRING_COMMENT);
}
<STRING_COMMENT>[ \t]+ {}
"「「"  {
    startLine = yytokenLine;
    startCol = yycolumnUtf8 - yylengUtf8 + 1;
    //printf("line = %d, col = %d\n", startLine, startCol);
    yymore_utf8();
    BEGIN(STRING_COMMENT);
}
<STRING_COMMENT>"」" {yymore_utf8();}
<STRING_COMMENT>"」"/"」」" { 
    yymore_utf8(); 
}
<STRING_COMMENT>"」」"  {BEGIN(INITIAL);printf("%d:%d: STR_LIT \"%s\"\n", startLine, startCol, trimStringToken(6));}
<STRING_COMMENT>\r?\n       { updateNewline(); yymore_utf8(); }
<STRING_COMMENT>{EXCLUDE_QUO}+      { yymore_utf8(); }
<STRING_COMMENT>"」"{EXCLUDE_QUO}   { yymore_utf8(); }


"名之曰"        { PRINT_TOKEN("NAME_IT %s", yytext);}
"是矣"          { PRINT_TOKEN("IS_THUS %s", yytext);}
"吾有"|"今有"    { PRINT_TOKEN("HERE_ARE %s", yytext);}
"昔之"          { PRINT_TOKEN("PAST %s", yytext);  }
"曰"            { PRINT_TOKEN("SAID %s", yytext);  }
"今"            { PRINT_TOKEN("SET %s", yytext);  }
"其"            { PRINT_TOKEN("ITS %s", yytext);  }
"者"            { PRINT_TOKEN("TOPIC %s", yytext);  }
"有"            { PRINT_TOKEN("HERE_IS_A %s", yytext);  }

"爻"  { PRINT_TOKEN("VAR_TYPE %s", yytext);  }
"數"  { PRINT_TOKEN("VAR_TYPE %s", yytext);  }
"長"  { PRINT_TOKEN("VAR_TYPE %s", yytext);  }
"言"  { PRINT_TOKEN("VAR_TYPE %s", yytext);  }
"元"  { PRINT_TOKEN("VAR_TYPE %s", yytext);  }
"列"  { PRINT_TOKEN("VAR_TYPE %s", yytext);  }
"術"  { PRINT_TOKEN("VAR_TYPE_FUNC %s", yytext);  }
"陰"  { printf("%d:%d: BOOL_LIT false\n",yytokenLine, yycolumnUtf8 - yylengUtf8 + 1);  }
"陽"  { printf("%d:%d: BOOL_LIT true\n",yytokenLine, yycolumnUtf8 - yylengUtf8 + 1);  }

"加"  { PRINT_TOKEN("EXP_MATH %s", "+"); }
"減"  { PRINT_TOKEN("EXP_MATH %s", "-"); }
"乘"  { PRINT_TOKEN("EXP_MATH %s", "*"); }
"除"  { PRINT_TOKEN("EXP_MATH %s", "/"); }
"所餘幾何"  { PRINT_TOKEN("EXP_MATH_OP %s", "%"); }
"於"  { PRINT_TOKEN("%s", "<-"); }
"以"  { PRINT_TOKEN("%s", "->"); }

"中有陽乎"  { PRINT_TOKEN("EXP_LOGIC %s", "||"); }
"中無陰乎"  { PRINT_TOKEN("EXP_LOGIC %s", "&&"); }
"不大於"    { PRINT_TOKEN("EXP_LOGIC %s", "<="); }
"不小於"    { PRINT_TOKEN("EXP_LOGIC %s", ">="); }
"不等於"    { PRINT_TOKEN("EXP_LOGIC %s", "!="); }
"大於"      { PRINT_TOKEN("EXP_LOGIC %s", ">"); }
"小於"      { PRINT_TOKEN("EXP_LOGIC %s", "<"); }
"等於"      { PRINT_TOKEN("EXP_LOGIC %s", "=="); }

"或若"      { PRINT_TOKEN("ELSE_IF %s", yytext); }
"若非"      { PRINT_TOKEN("ELSE %s", yytext); }
"若"        { PRINT_TOKEN("IF %s", yytext); }
"恆為是"    { PRINT_TOKEN("WHILE_TRUE %s", yytext); }
"為是"      { PRINT_TOKEN("FOR %s", yytext); }
"遍"        { PRINT_TOKEN("TIMES %s", yytext); }
"乃止"      { PRINT_TOKEN("BREAK %s", yytext); }
"乃得"      { PRINT_TOKEN("RETURN %s", yytext); }
"云云"|"也"|"矣"  { PRINT_TOKEN("END %s", yytext); }

"欲行是術"        { PRINT_TOKEN("TO_PERFORM_FUNC %s", yytext); }
"必先得"          { PRINT_TOKEN("REQUIRE_ARGS %s", yytext); }
"乃行是術曰"|"乃是術曰"  { PRINT_TOKEN("FUNC_BEGIN %s", yytext); }
"是謂"            { PRINT_TOKEN("FUNC_END_FOR %s", yytext); }
"之術也"          { PRINT_TOKEN("FUNC_END %s", yytext); }
"施"              { PRINT_TOKEN("CALL %s", yytext); }

"夫"        { PRINT_TOKEN("THOSE %s", yytext); }
"充"        { PRINT_TOKEN("PUSH %s", yytext); }
"取"        { PRINT_TOKEN("TAKE %s", yytext); }
"之長"      { PRINT_TOKEN("LENGTH %s", yytext); }
"之"        { PRINT_TOKEN("INDEX %s", yytext); }
"書之"      { PRINT_TOKEN("PRINT %s", yytext); }

{digit}+ {
    ScientificNotation sci;
    if (!chineseToArabic(yytext, &sci)) {
        PRINT_TOKEN("NUMBER_LIT %s", sciToStr(&sci));
    } else {
        printf("%d:%d: ERROR parsing number\n", yytokenLine, yycolumnUtf8 - yylengUtf8 + 1);
    }
}

[ \t]+      {}
\r?\n       { updateNewline(); }
"。"|"，"  {}
^{UTF8_BOM}  {  /* Skip UTF-8 BOM at file start */ strcpy(bom_cache, yytext); yycolumnUtf8 = 0; /* ensure BOM doesn't shift columns */ }

<<EOF>>     { yyterminate(); }

{ALL_UTF8} { PRINT_TOKEN("UNKNOWN CHAR %s", yytext); }
. { PRINT_TOKEN("UNKNOWN CHAR %s", yytext); }

%%
/*  C Code section */
int yywrap(void) {
    return 1;
}