# Wenyan Compiler

一個以 C 撰寫的[文言文程式語言（wenyan-lang）](https://github.com/wenyan-lang/wenyan)編譯器。使用 Flex / Bison 做詞法與語法分析，產生 LLVM IR，再經 `llc` 與 `gcc` 編譯成原生執行檔。

```
source.wy ──(Flex/Bison)──▶ source.ll ──(llc)──▶ source.o ──(gcc + runtime)──▶ 執行檔
```

## 範例

```
吾有兩數。曰零。曰一。名之曰「甲」。曰「乙」。

為是 五 遍。
    加「乙」於「甲」。昔之「甲」者。今其是矣。
    吾有一數。曰「甲」。書之。
云云。
```

```shell
$ ./build/wyc count.wy && ./count
1
2
3
4
5
```

## 功能

- 型別：數、長（整數）、元（浮點數）、言（字串）、爻（布林）、列（陣列）、術（函式）；數值運算自動升級 I32 → I64 → F64
- 中文數字字面值（如 `二`、`一·一`）
- 變數宣告、多值宣告、賦值（`昔之…者。今…是矣。`）
- 算術（加減乘除、所餘幾何）、比較、邏輯運算
- 控制流：`若` / `或若` / `若非`、`為是…遍`、`恆為是`、`乃止`
- 函式定義、呼叫與回傳（`乃得`），支援捕獲外部變數
- 中文錯誤訊息，並標出錯誤位置

## 建置

需要：`cmake` ≥ 3.10、`flex` ≥ 2.6、`bison` ≥ 3.6、支援 C11 的 `gcc`、`llvm`（`llc`）≥ 14

```shell
cmake -B build -S .
cmake --build build
```

<details>
<summary>安裝相依套件</summary>

**Windows（MSYS2 UCRT64）**
```shell
pacman -S bison flex mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-llvm
```

**Ubuntu / Debian**
```shell
sudo apt install cmake flex bison gcc llvm
```

**macOS**
```shell
brew install cmake flex bison llvm
```
</details>

建置產物：

| 檔案 | 說明 |
|------|------|
| `build/wyc` | 編譯器前端指令，一步從 `.wy` 產出執行檔（執行時需要 `llc`、`gcc` 在 PATH 中） |
| `build/wy` | 核心編譯器，將 `.wy` 轉成 LLVM IR（`.ll`） |
| `build/lib/libwenyan-runtime.a` | 執行期函式庫（輸出、字串、陣列操作） |
| `build/tools/lexer/wy-lex` | 獨立的詞法分析器，印出 token 串流 |

## 使用方式

```shell
wyc <源書.wy> [成器]
```

| 選項 | 說明 |
|------|------|
| `-v` | 顯示詳細編譯過程 |
| `-l` | 顯示 lexer 解析的 token |
| `-x` | 只做詞法分析 |
| `-c` | 彩色輸出 |
| `-h` | 顯示說明 |

只想看產生的 LLVM IR：

```shell
./build/wy source.wy source.ll
```

## 專案結構

```
src/
├── compiler.l          Flex 詞法規則
├── compiler.y          Bison 語法規則與語意動作
├── main.c              語意動作核心、程式進入點
├── wyc.c               wyc 指令（串接 wy → llc → gcc）
├── scope.c             符號表 / 作用域管理
├── object.c            值與型別系統
├── value_data.c        多值宣告
├── expression.c        運算式 IR 產生
├── control/            if / for / while / 函式的 IR 產生
├── lib/                IR 輸出、中文數字轉換、UTF-8 等工具
└── wy_rt/              執行期函式庫
tools/lexer/            獨立詞法分析器 wy-lex
cmake/                  安裝後供其他 CMake 專案使用的 package config
lib/                    第三方函式庫
```

