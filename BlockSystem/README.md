# BlockSystem — AST 代码积木模块（阶段零 · 结构规范）

> **本目录是 Git 子模块（Submodule）的根目录。**
> 它是一个**自包含沙盒**：内部代码与资源**严禁**引用 `res://BlockSystem/` 之外的任何路径
> （不引用主工程的 autoload、输入映射、场景、主题、图标或脚本）。
>
> 依赖方向恒定为单向：**主游戏工程 → BlockSystem**。反向依赖一律视为架构违规。

---

## 1. 目录树

```text
res://BlockSystem/
├── README.md                     ← 本规范
├── _bootstrap_structure.gd       ← 开发期工具（EditorScript），不属于任何一层，不参与运行时
├── _demo_workspace.gd / .tscn    ← 开发期演示场景：AST -> UI -> AST 整链路手动验证
│
├── Core/                         纯数据层：AST 核心数据结构与解析器
├── Logic/                        交互层：拖拽（Drag & Drop）与重做逻辑
├── Art/                          美术专区
│   ├── Themes/                   .theme 与 StyleBox
│   ├── Palettes/                 .tres 配色资源
│   └── Icons/                    图标资源
└── Prefabs/                      组装好的代码块模板场景 (.tscn)
```

每个叶子目录内都有一个隐藏的 `.gitkeep`，用于让 Git 跟踪空目录 —— **不要删除**。

---

## 2. 各目录契约

### `Core/` — 纯数据层
- 内容：AST 节点定义、语法校验、序列化 / 反序列化、解析器。
- 类型约束：只允许 `RefCounted`，**禁止 `extends Node`**。
- 依赖约束：**零引擎场景依赖** —— 不得触碰 `SceneTree`、`Node`、`Control`。
- 收益：可在 headless 中脱离场景单测，且天然可序列化。
- 命名：`AST_` 前缀，类名与文件名一致（`AST_Node.gd`、`AST_Statement.gd`、`AST_Command.gd`、`AST_Expression.gd`、`ASTManager.gd`）。
- 全局入口：`ASTManager` 是 `class_name` + 全静态方法的门面，任意脚本可直接调用
  `ASTManager.parse_json_to_ast(text)` / `ASTManager.serialize_ast_to_json(ast)`，**无需注册 Autoload**。
  Godot 硬性要求 Autoload 必须继承 `Node`（否则启动即报 `does not inherit from 'Node'`），
  与本层「禁止 extends Node」冲突，故本模块不注册 Autoload。
- 已实现（阶段一）：`AST_Node`（基类，持 `type` 字段）、`AST_Statement`（`condition` + `body`）、
  `AST_Command`（`opcode` + `args`）、`AST_Expression`（`operator` + `left` + `right` + `value`）、
  `ASTManager`（JSON ⇄ AST）。
- 已实现（阶段四）：`AST_BlockSchema.gd` —— **纯 AST 知识**：节点种类、子节点角色
  （`condition` / `body` / `left` / `right`）、调色板类别判定（运算符分组与叶子语义）。
  它**不知道**任何 .tscn 路径与插槽属性名 —— 那些属于视图层。
  这样 Core 仍保持零 Node 依赖，两侧可以各自单测。
- 已实现（阶段五）：`AST_TypeInference.gd`（结果类型推断 `Boolean / Number / Unknown`，
  供插槽强类型校验）与 `AST_BlockSchema.required_roles()`（哪些角色是必填的，
  交给视图补占位）+ `role_requires_boolean()`。三条都是纯静态函数，可 headless 单测。

### `Logic/` — 交互层
- 内容：拖拽控制器、吸附/对齐求解、放置区探测、撤销重做栈、画布交互。
- 类型约束：可继承 `Node` / `Control`。允许依赖 `Core/` 与 `Art/`。
- **美术解耦硬约束**：不得硬编码任何颜色、字号、圆角、间距、图标路径。
  一切视觉参数只能通过 `Art/` 中的资源（Theme / Palette）在运行时注入。
- 命名：以职责结尾，例：`block_drag_controller.gd`、`snap_solver.gd`、`drop_zone_detector.gd`、`undo_stack.gd`。
- 已实现（阶段二）：`BlockStyleSpec.gd`（表达式 StyleBoxFlat 规范：margin T/B=0、L/R=8；
  border T/B=0、L/R=2；底色 alpha 20%~40%；供校验与 CI 用）、
  `ExpressionUI.gd` / `StatementUI.gd`（组件基座，只认插槽、**不生成节点树**）。
- 已实现（阶段三）：`BlockDragDrop.gd`（拖放通用逻辑：载荷、快照、垂直插入位、横向三分区、状态变体名）。
  `ExpressionUI` / `StatementUI` 各自实现 `_get_drag_data` / `_can_drop_data` / `_drop_data`
  三个回调（Godot 只把它们派发给鼠标下的 Control，**无法**写在共用基类里）。
- **拖放状态一律用 `theme_type_variation` 切换，禁止用 `modulate` 改色**。
  唯一例外是拖拽快照的半透明（它不是积木状态，而是快照），且透明度取自主题项 `BlockDrag/preview_modulate`。
- 视图重排完成后发 `reorder_requested(action, index, payload)` 信号发布「模型变更意图」。
- 已实现（阶段四）：`BlockSyncEngine.gd`（**AST ⇄ UI 双向同步引擎**，Node）——
  `build_ui_from_ast()` 递归实例化 `Prefabs/` 模板并按角色挂进插槽，用
  `await get_tree().process_frame` 分帧加载（`blocks_per_frame` 可调，默认每块一帧）；
  `build_ast_from_ui()` 递归遍历 UI 的挂载关系全量重建 AST，并接住 `reorder_requested`
  在拖拽后自动重建（`ast_rebuilt` 信号）。
  另有 `CommandUI.gd`（`AST_Command` 的视图，补齐了阶段二缺失的指令积木）。
- **积木 UI 协议**（新增积木只需满足它，引擎不认识具体类名）：
  `set_palette(palette)` / `bind_model(model)` / `get_model()`。
  `ExpressionUI` / `StatementUI` / `CommandUI` 三个挂载脚本都实现了它。
- 分层说明：`build_ui_from_ast` 要 `instantiate()` 场景与 `await get_tree().process_frame`，
  `RefCounted` 上连 `get_tree()` 都不存在，所以它**必须**在视图层；
  放进 `Core/` 会直接违反 §2 的 Core 约束。纯 AST 部分已下沉到 `Core/AST_BlockSchema.gd`。
- 已实现（阶段五）：`SlotUI.gd`（插槽 / 退化占位，`Prefabs/SlotUI.tscn`）—— 一手管**强类型落点**
  （`_can_drop_data` 查种类白名单 + 是否要求布尔结果，不符则切 `SlotRejected` 变体），
  一手管**结构退化**（必填操作数被拖走时由属主实例化它填补空位）。
  实现上它分成两种身份，不能混：`transient_placeholder = false` 是预制体里手搭的**常驻插槽**
  （If 条件槽，装进积木后留在原地承接）；`true` 是 `create()` 造的**临时占位**（装进积木后自我销毁）。
  常驻插槽一旦被销毁，属主的 `condition_slot` 引用就悬空了。
- 可选协议 `repair_slot(container)`：属主判断「这容器是不是我的必填槽位、现在空了吗」，
  在积木被摘走之后由 `BlockDragDrop.repair_after_removal()` 向上查找属主并调用。

### `Art/` — 美术专区
- `Themes/`：`Theme` 资源 + StyleBoxFlat。注意 Godot 4 的 `.theme` 是**二进制**扩展名
  （文本内容会被报 `Unrecognized binary resource file`），因此本模块统一用**文本 `.tres`** 存 Theme，保证 Git 可 diff。
- `Palettes/`：`palette_*.tres` 配色资源，以及定义其数据结构的 `BlockPalette.gd`。
- `Icons/`：统一为 `.svg`（矢量，缩放不糊）或 `.png`。
- **逻辑解耦硬约束**：本目录内资源**不得挂载行为脚本**，不得包含行为逻辑。
  美术资源是纯被动数据，只被 `Logic/` 读取，永不主动驱动逻辑。
  唯一例外：定义美术数据结构的 `Resource` 类（目前仅 `BlockPalette.gd`），
  它只含 `@export` 字段与取值方法，目的是让美术能在编辑器中配置 `.tres`。
- 已实现（阶段二）：`BlockPalette.gd` + `palette_default.tres`（五类颜色 + alpha 区间硬约束）、
  `block_stylebox_expression.tres`（合规几何）、`block_theme.tres`（`ExpressionBlock` type variation）。
- 已实现（阶段三）：`block_stylebox_expression_hovered.tres` / `block_stylebox_expression_wrapped.tres`
  （悬停 / 即将被包裹两态的样式，几何与透明度仍守规范）、主题里的 `ExpressionBlock_Hovered` /
  `ExpressionBlock_Wrapped` 变体、`StatementBlock_Hovered`（把 VBox 的 `separation` 从 4 撑到 12，
  作为垂直插入的落点提示）、以及 `BlockDrag/preview_modulate`（拖拽快照透明度）。
  换一个"落点反馈长什么样"，只需要改这些 `.tres`，不用动一行代码。

### `Prefabs/` — 组装层
- 内容：把 `Core` 数据、`Logic` 行为、`Art` 外观三者**首次也是唯一**组装起来的 `.tscn`。
- 这是唯一允许同时引用三层的地方（但不得引用沙盒之外的路径）。
- 命名：`block_<类别>.tscn`，例：`block_motion.tscn`、`block_loop.tscn`、`workspace.tscn`。

---

## 3. 资源命名约定

| 目录 | 前缀 / 后缀 | 示例 |
| --- | --- | --- |
| `Core/` | `AST_*.gd` | `AST_Statement.gd` |
| `Logic/` | `*_controller.gd` / `*_solver.gd` | `snap_solver.gd` |
| `Art/Themes/` | `*.tres`（Theme / StyleBox） | `block_stylebox_expression.tres` |
| `Art/Palettes/` | `palette_*.tres` + `BlockPalette.gd` | `palette_default.tres` |
| `Art/Icons/` | `icon_*` | `icon_loop.svg` |
| `Prefabs/` | `block_*.tscn` | `block_motion.tscn` |

文件名一律 `snake_case`，不使用空格与中文。（Godot 的 `class_name` 仍用 `PascalCase`。）

---

## 4. 五条硬性解耦规则

1. **沙盒封闭**：`BlockSystem/` 内不得出现指向 `res://BlockSystem/` 之外的 `res://` 路径（`load`、`preload`、`ext_resource` 皆然）。
2. **Core 无引擎依赖**：`Core/` 不得继承或引用 `Node` 家族。
3. **Logic 无美术字面量**：颜色 / 字号 / 图标路径等视觉值一律来自 `Art/`，不得写死在逻辑脚本里。
4. **Art 无逻辑**：`Art/` 内的 `.tres` / `.theme` 不得挂脚本。
5. **Prefabs 独占组装权**：只有 `Prefabs/` 可以同时引用 Core + Logic + Art。

### 违规自检（可在 CI 或提交前手动执行）

```bash
# 规则 1：查找越界引用（期望无输出）
rg -n 'res://' BlockSystem -g '!*.import' -g '!*.md' | grep -v 'res://BlockSystem'

# 规则 2：Core 层出现 Node 依赖即为违规（期望无输出）
rg -n 'extends Node|extends Control|get_tree\(\)' BlockSystem/Core

# 规则 4：Art 资源不得挂脚本（期望无输出）
rg -n 'script\s*=' BlockSystem/Art
```

---

## 5. 引导脚本用法

`_bootstrap_structure.gd` 是一个 `EditorScript`，**幂等**：已存在的目录与文件不会被覆盖。

运行方式（任选其一）：
1. 在脚本编辑器中打开该文件 → 菜单 **File > Run**（快捷键 `Ctrl+Shift+X`）。
2. 在 **FileSystem** 面板右键该文件 → **Run**。

它会在输出面板打印建成的目录树。脚本本身是开发期工具，**不属于任何一层**，也不参与运行时逻辑。

### 纯命令行等价方案（无编辑器环境 / CI）

```bash
mkdir -p BlockSystem/{Core,Logic,Art/{Themes,Palettes,Icons},Prefabs}
for d in Core Logic Art/Themes Art/Palettes Art/Icons Prefabs; do
  [ -f "BlockSystem/$d/.gitkeep" ] || printf '# 占位文件\n' > "BlockSystem/$d/.gitkeep"
done
```

---

## 6. Git 子模块说明

- 本目录整体作为一个仓库被主工程以 `git submodule` 方式挂载。
- 空目录不会被 Git 跟踪，因此每个叶子目录都放置了 `.gitkeep`。
- `.godot/` 与 `*.import` 的忽略规则由主工程根部的 `.gitignore` 覆盖，子模块内无需重复。
- 新增文件时请**严格放入 §1 表中对应的目录**；确需新增子目录时，先更新本 README 的目录树。

---

## 7. 已知引擎行为（Godot 4.7.2 实测记录）

以下几条是本模块踩过并已绕开的坑，改动相关代码前请先读一遍。

### 7.1 `get_theme_stylebox(name)` 单参调用**不会**查 type variation

实测（theme 挂在节点或父节点、属性赋值先后顺序，均不影响结论）：

| 调用 | 结果 |
| --- | --- |
| `get_theme_stylebox("panel")` | 默认主题样式（bg `0.1/0.1/0.1/0.6`、margin 0、border 0），**变体被忽略** |
| `get_theme_stylebox("panel", "ExpressionBlock")` | 变体样式 ✓ |
| `get_theme_stylebox("panel", "PanelContainer")` | 变体样式 ✓ |

**规则**：取样式必须显式传入 theme type。`ExpressionUI` 用
`get_theme_stylebox(&"panel", get_theme_type_variation())`；
漏传会静默拿到默认主题的样式，美术配的几何全部失效且不报错。

### 7.2 导出节点引用必须在节点头声明 `node_paths`

```ini
[node name="IfBlockUI" type="VBoxContainer" node_paths=PackedStringArray("condition_slot", "body_container")]
condition_slot = NodePath("ConditionSlot")
```

只写 `NodePath(...)` 而不加 `node_paths=...`，加载后该属性恒为 `null`。
（在编辑器里拖拽挂插槽时 Godot 会自动补上这一项，手写场景文件时必须自己写。）

### 7.3 `.theme` 是二进制扩展名

`ResourceSaver.save(theme, "x.theme")` 写出的是 `RSRC` 二进制；手写的文本 `.theme`
会被报 `Unrecognized binary resource file`。本模块统一用**文本 `.tres`** 存 Theme。

### 7.4 JSON 数字一律读成 float

`JSON.parse_string("3")` 返回 `float`（不是 `int`）。`ASTManager` 已在读回路径做整数归一化，
上限 2^53，详见 `ASTManager._normalize_number()` 的注释。

### 7.5 GDScript 不允许子类覆写父类常量

`const TYPE := "x"` 在子类里重名会直接报 `Parse Error: The member "TYPE" already exists in parent class`。
`AST_Node` 因此用实例字段 `type` + 各子类 `_init()` 赋值。

### 7.6 本地样式覆盖的优先级高于主题变体

`add_theme_stylebox_override("panel", box)` 是**本地覆盖**：它一旦存在，主题（含 type variation）
的同名条目就被完全忽略。

所以「常态用调色板上色、悬停 / 包裹切状态变体」要成立，切变体时必须
**先 `remove_theme_stylebox_override("panel")`**，否则切了也毫无视觉变化。
`ExpressionUI._set_interaction_state()` 就是这么做的，别把这一步"优化"掉。

### 7.7 `set_drag_preview()` 要求视口正处于拖拽中

`Control.set_drag_preview()` 内部断言 `viewport.gui_is_dragging()`。引擎发起拖拽时它已经是 `true`，
但如果有人直接调用 `_get_drag_data()`（测试、工具代码），它就是 `false`，会打印
`Condition "!get_viewport()->gui_is_dragging()" is true`。

比报错更危险的是：先 `hide()` 源节点、再挂快照，一旦挂快照失败，源节点就**永久隐藏**了
（不会有 `DRAG_END` 来恢复它）。`BlockDragDrop.begin_drag()` 因此先检查 `gui_is_dragging()`，
不满足就直接返回 `null`，由 `_get_drag_data()` 放弃这次拖拽。

### 7.8 浮点比较必须带容差

`Color` 内部是 float32，`.tres` 里写的 `0.4` 读回来是 `0.40000000596`，
直接跟 `0.4` 比会判成"越界"。`BlockStyleSpec` 因此带 `ALPHA_TOLERANCE`。

### 7.9 GDScript 的 lambda 按值捕获局部变量

```gdscript
var frames: int = 0
process_frame.connect(func() -> void: frames += 1)  # 递增的是 lambda 自己的副本
```
用命名方法或放进 Array/Dictionary（引用类型）里再捕获，否则计数器永远是 0。

### 7.10 槽位不一定挂在积木的直接子节点上

`ExpressionBlockUI` 的左操作数槽是 `Row/LeftSlot` —— 中间隔着一层布局容器。
所以「找槽位的属主积木」必须**向上查找**，不能只看 `get_parent()`：
只看一层会让结构退化逻辑静默失效（占位永远补不上，而且不报错）。
见 `BlockDragDrop.repair_after_removal()`。

### 7.11 `child_exiting_tree` 触发时子节点还没真正离开

在信号回调里立刻 `get_children()` 看到的还是旧状态 —— 实测：把条件积木拖走后，
条件槽依然显示「已填」。刷新逻辑要 `call_deferred()` 延到帧末再跑。
（`child_entered_tree` 同理会偏早，一并延后最省心。）

### 7.12 虚线边框需要贴图，StyleBoxFlat 做不到

`StyleBoxFlat` 只有实线边框，没有 dash 参数。降级占位槽目前用的是
`block_stylebox_slot_placeholder.tres`（灰底 + 灰实线边）。
要做成真正的灰色虚线，把主题里 `SlotPlaceholder/styles/panel` 换成一张
`StyleBoxTexture`（虚线边框贴图）即可 —— **不用改任何代码**，
因为插槽只认 `theme_type_variation`，不认 StyleBox 的具体类型。

---

## 8. 怎么新增一种积木

同步引擎是数据驱动的，大多数改动不需要碰引擎代码。

**在已有种类里加变体**（例如把逻辑积木细分成 and / or / not）：完全不用改引擎，只要
Art 里加一个 type variation、Logic 里复用 `ExpressionUI`、`Core/AST_BlockSchema.gd`
的运算符表加一项即可。

**新增一个 AST 节点种类**（第 4 种结构）需要五步：

1. **Core**：加 `AST_*.gd` 数据类；在 `AST_BlockSchema.gd` 补
   `kind_of()` / `child_roles()` / `palette_category()` 三个分支。
2. **Art**：加一个 StyleBoxFlat，并在 `block_theme.tres` 里注册 type variation
   （形如 `EventBlock/base_type = &"PanelContainer"` + `EventBlock/styles/panel = ...`）。
3. **Logic**：写挂载脚本，实现**积木 UI 协议**
   `set_palette()` / `bind_model()` / `get_model()`。
4. **Prefabs**：做 `.tscn`，根节点挂脚本、设 `theme_type_variation`、把插槽 `@export`
   指向场景内节点（节点头必须写 `node_paths=PackedStringArray(...)`，见 §7.2）。
5. **引擎**：`BlockSyncEngine.TEMPLATES` 加一行「种类 → 模板路径」，
   新角色再往 `ROLE_SLOTS` 加一行「角色 → 插槽属性名」；
   编译侧 `_compile_node()` 加一个分派分支（它目前按三个具体类分派）。

**已知的界面表现缺口**（属于美术/排版，不是逻辑缺陷）：
`IfBlockUI` 目前是一个裸 `VBoxContainer`，`body_container` 没有缩进、也没有 C 形外框，
所以嵌套语句与同级语句在视觉上是齐平的。要做出积木编辑器的手感，
需要在 Prefab 里给语句体加外层 Panel / MarginContainer 与缩进 —— 这一步只动 Art 与 Prefabs。

