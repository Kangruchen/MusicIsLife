---
applyTo: '**'
---
Provide project context and coding guidelines that AI should follow when generating code, answering questions, or reviewing changes.

当编写新代码时或我要求你重构或审查代码时，请遵循以下原则：
类型提示: 为所有变量、函数参数和返回值添加静态类型提示。这对于代码补全和错误检查至关重要。
示例: `var health: int = 100` 或 `func take_damage(amount: int) -> void:`
命名约定:
    变量和函数: 使用 `snake_case` (蛇形命名法)，例如 `player_speed`、`handle_input()`。
    类和节点: 使用 `PascalCase` (帕斯卡命名法)，例如 `PlayerController`、`EnemySpawner`。
    常量: 使用 `UPPER_SNAKE_CASE` (大写蛇形命名法)，例如 `MAX_HEALTH`。
注释: 对复杂的逻辑或重要的函数添加简洁明了的注释，解释其工作原理。
代码结构:
    优先使用信号（Signals）进行节点间的解耦通信。
    将相关的函数组织在一起，并使用空行分隔不同的逻辑块。
获取节点:
    在 `_ready()` 函数中使用 `@onready` 注解或赋值来获取节点引用，避免在 `_process()` 或 `_physics_process()` 中重复调用 `get_node()`。
    示例: `@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D`
综合考虑代码的可读性、可扩展性、性能和维护性，确保代码简洁高效。
遵循Godot引擎的最佳实践和设计模式，确保代码与引擎的工作方式一致。
始终使用Godot的内置功能和API，而不是依赖外部库，除非绝对必要。
对于相对简单的功能修改，尽量不要创建.md文件，而是在聊天窗口中直接说明修改内容。
当开发新功能时，如果需要创建.md文件，请确保内容简洁明了，避免冗长复杂的说明。
尽可能复用现有的信号和函数等，避免大量创建新的代码文件。
对于场景、UI等始终存在的元素，尽可能在场景树中直接创建对应节点而非在代码中动态生成。
对于敌人等可复用的元素，优先使用预制场景（PackedScene）进行实例化。