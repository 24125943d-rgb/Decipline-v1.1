# 工程目标

## 角色按关联 BlockSystem 实例行动

- 已实现显式 start/stop/is_running：BlockLab 启动快照 → 严格验证 → 独立 RefCounted runner → 本角色 CombatHost → execute。不是角色脚本，绝不替换 Character 脚本，默认 idle。
- validate() 保留 compile-only；validate_for_character() 严格检查但不执行。可创建宿主，不添加 Attack/Movement/Vision。
- state_changed、execution_error、completed 信号；状态 idle/running/finished/stopped/error。双 start 拒绝；stop/unlink/换链接/宿主退出/积木实例退出/组件退出取消追逐，token 隔离旧协程。finished 表示程序结束，不保证命中。
- UI 修改不热更新；剩余交互按钮、复杂寻路及完整实玩验收。未自动开启场景 AI，未修改视野/相机/立场。

### 显式运行示例

假设节点为 `/root/Main/Character/Decipline`、`/root/Main/BlockLab`：
```gdscript
var lab: Node = get_node("/root/Main/BlockLab")
var mock: GDScript = load("res://scripts/combat_ai_mock.gd")
var manager: GDScript = load("res://BlockSystem/Core/ASTManager.gd")
await lab.build(manager.from_dictionary(mock.get_character_program_ast()))
var component: Node = get_node("/root/Main/Character/Decipline")
component.link(component.get_path_to(lab))
component.max_iterations = 10 # 0 = unlimited
if component.validate_for_character().ok:
    component.start()
# component.stop(); component.unlink()
```
专用示例使用 Enemy.visible.exists/closest、Attack-range、Attack/Chase；通用旧 mock 不变。执行链已经接入，但演示场景默认不自动启动。

### 当前组件使用

基础角色及其属性角色预制体带有无关联的 `Decipline` 子节点。为 `block_lab_path` 设置相对此组件的 BlockLab 节点路径，或调用 `link(path)`。调用 `validate()` 返回 `ok/status/problems`；调用 `unlink()` 解除关联。默认不运行任何角色行为。编译检查不保证运行宿主的方法或属性已存在。
