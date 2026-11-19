# 技术架构（当前：Ground-Air Hybrid 机动原型）

引擎：Godot 4.7.2 stable（macOS universal），GDScript，物理引擎 Jolt（`project.godot` 显式指定）。

## 1. 分层

```
 PlayerBrain / (AIBrain, 后续阶段) / 测试脚本
        │  MechCommand（移动方向、上升/下降、跳跃/冲刺沿、期望朝向）
        ▼
 MechMotor  (CharacterBody3D, MOTION_MODE_GROUNDED)
   ├─ 运动状态机 GROUNDED / GROUND_DASH / TAKEOFF / AIRBORNE / HOVER / AIR_DASH / FALLING / LANDING
   ├─ EN 资源（消耗 / 延迟 / 恢复 / 耗尽）
   ├─ 碰撞（move_and_slide）、上升上限、地图绝对边界、卡死恢复
   └─ MovementModifier 聚合（速度/加速度/转向/重力倍率 + 阻断标志）
        ▲                         ▲
        │ add_modifier / apply_impulse（唯一入口）
 CombatStateMachine（READY / ACTION / STAGGER，占位层）
        
 MechVisual（只读运动状态：倾斜、推进器发光、镜头过近淡出）——不能阻断控制
 TargetingSystem（锁定/切换/丢失）── TeamRules.is_hostile / get_valid_targets
 CameraRig（自由 / 锁定 / 遮挡 / FOV）  DebugHud（调试面板 + 离屏提示）
```

| 文件 | 职责 |
|---|---|
| `scripts/movement/mech_movement_profile.gd` | 机动数据 Resource（不含逻辑） |
| `scripts/movement/mech_command.gd` | 单帧意图；玩家、AI、测试共用 |
| `scripts/movement/movement_modifier.gd` | 技能/战斗对移动的限制与修正 |
| `scripts/movement/mech_motor.gd` | 共享运动核心 |
| `scripts/movement/mech_factory.gd` | 由数据组装机体实体（玩家与 AI 相同，仅 Brain 不同） |
| `scripts/movement/mech_visual.gd` | 占位程序化外形（灰盒） |
| `scripts/combat/combat_state_machine.gd` | 战斗/受击层骨架 |
| `scripts/core/team_rules.gd` | 敌对与有效目标接口（MatchRules 的最小前身） |
| `scripts/core/input_setup.gd` | 输入映射（autoload） |
| `scripts/control/player_brain.gd` | 键鼠 → MechCommand |
| `scripts/targeting/targeting_system.gd` | 锁定 |
| `scripts/camera/camera_rig.gd` | 镜头 |
| `scripts/ui/debug_hud.gd` | 调试 HUD、锁定框、离屏敌人提示 |
| `scripts/level/*` | 灰盒关卡、地图边界、测试靶、测试弹丸夹具 |
| `tests/test_runner.gd` | 自动化验收测试 |
| `scripts/debug/autopilot.gd` | 真实渲染下的脚本化演示 + 截图 + 帧率统计 |

## 2. 设计决策记录

- **D-01 悬停不切换 FLOATING。** 全程 `MOTION_MODE_GROUNDED`；悬停是“垂直速度制动到 0 + 持续耗 EN”的状态。地面识别、坡面吸附、着陆检测保持原生行为。
- **D-02 原点在脚底。** 起飞高度、上升上限、离地高度都以脚底计算；地图天花板约束的是头顶（`ceiling_y - BODY_HEIGHT`）。
- **D-03 战斗层只通过修正器影响移动。** `CombatStateMachine` 不写 `velocity`（T09 有静态检查）。修正器只能做乘法和阻断；重力倍率被钳制在 [0.5, 3]，速度倍率 [0, 2]，因此任何技能都无法制造零重力或无限滞空。
- **D-04 上升上限 = min(起飞点 + 10 m, 地图天花板 - 机体高度)。** 接近上限时按 `hover_brake` 预先减速：v ≤ √(2·brake·剩余高度)，不会过冲。
- **D-05 EN 恢复延迟在着陆时重置。** 规格只写“恢复延迟 0.8 s”。实现为：最后一次消耗**或着陆**后 0.8 s 开始恢复，避免长时间坠落后一落地就立刻满速回能。属于小歧义，采用默认值，可改。
- **D-06 受控下降需要 EN。** 有 EN 时按下降键以 `descend_speed` 稳定下沉（不耗 EN，着陆柔和）；EN 为 0 时下降键无效，纯重力坠落。
- **D-07 只有“松开上升键”才进入悬停。** 单纯跳跃（点按 Space）不会悬停，走自由抛物线；使用过推进（按住 Space、空中冲刺）后，松键会自动悬停并耗 EN。
- **D-08 镜头的所有自动旋转限速 200°/s**，包括锁定跟随、目标切换、解锁回归。手动鼠标在自由模式下不受限；锁定模式下转为 ±25°/±15° 的偏移量，0.8 s 后回正。
- **D-09 锁定取景采用角度插值**：视线方向 = slerp(指向玩家胸口, 指向目标, w)，w 受限以保证玩家胸口在中心 26° 内；锁定时镜头位置俯仰钳制在 [-35°, 15°]，仰视高空目标改为“抬头看”而非“镜头钻到地面”。
- **D-10 遮挡**：从注视点做球形扫掠，遇遮挡立刻拉近，脱离遮挡后平滑拉远。拉近到 2.8 m 以下时尝试备选位置：抬高；锁定时还会尝试左右摆开。镜头臂方向经平滑后再扫掠一次，保证摆动过程中不进入几何体。1.2–3 m 时机体淡出。
- **D-11 灰盒关卡由代码生成**（`GrayboxBuilder`），玩法场景与测试使用同一布局。它**不是**三张正式地图之一。
- **D-12 测试弹丸夹具**（`TestProjectile`，F6 开关）只用于 M04 规避验收：直线飞行、每帧射线扫掠，统计命中与规避，**无伤害系统**。预判射击使用迭代求解拦截点。
- **D-14 镜头距离三档**（7.5 / 10 / 13 m，默认 10 m），按 `Z` 循环切换，平滑过渡。滚轮保留给锁定目标切换，避免冲突。锁定时镜头位置下压上限从 15° 收窄到 8°，避免在 10 m 以上的臂长下贴地触发遮挡拉近。
- **D-13 输入映射在 autoload 中注册**，而非序列化在 `project.godot` 中，便于阅读和修改。

## 3. 碰撞层

| 层 | 名称 | 内容 |
|---|---|---|
| 1 | world | 静态几何体（镜头遮挡、视线检测只看这一层） |
| 2 | mechs | 机甲（`MechMotor`） |
| 3 | targets | 测试靶 |

机甲的碰撞掩码为 1|2|4。

## 4. 占位资源

全部为程序化几何体（BoxMesh / SphereMesh）、引擎内置天空和自写的网格 shader（`shaders/graybox_grid.gdshader`），不含第三方资源，不存在许可证问题。**这些不是最终美术**，替换计划属于阶段 7。


---

# 阶段 2b：战斗层

```
 Brain ──MechCommand（attack / skill / parry / ult 按键沿、guard 持续按住）──▶ CombatStateMachine
                                                                              │ 只通过以下接口影响机动：
                                                                              │  · MovementModifier（限制 + forced 运动修正）
                                                                              │  · MechMotor.apply_impulse / apply_hitstop / consume_en
 检测：Hitbox 形状扫掠（攻击活动段）/ Projectile 射线 ──HitInfo──▶ DamageSystem.resolve()
                                                                     │ 结算顺序：can_damage → 招架 → 格挡 → 命中
                                                                     ▼
                                                     Health / 双方 CombatStateMachine 的反应
                                                                     │
                                                          CombatEvents（autoload 事件总线）
                                                ┌────────────┬───────────────┼──────────────┐
                                           CombatFeedback   CombatHud     MechVisual     伤害日志 / 测试
```

| 文件 | 职责 |
|---|---|
| `scripts/combat/attack_definition.gd` / `combat_profile.gd` / `ultimate_definition.gd` | 数据 Resource |
| `scripts/combat/combat_state_machine.gd` | READY / ATTACK / GUARD / PARRY / STAGGER / OFFBALANCE / ULT_WINDUP / DEAD 状态（另保留 2a 的 ACTION） |
| `scripts/combat/damage_system.gd` | 唯一的伤害结算入口 |
| `scripts/combat/hit_info.gd` / `health.gd` / `hurtbox.gd` | 命中请求、生命值、受击判定区（物理层 5） |
| `scripts/combat/projectile.gd` | 可被招架折射的弹丸 |
| `scripts/combat/ultimate_system.gd` | 通用的低血量大招流程 |
| `scripts/core/combat_events.gd` | 事件总线（autoload `CombatEvents`） |
| `scripts/feedback/combat_feedback.gd` / `procedural_audio.gd` | 火花、占位音效、震屏 |
| `scripts/control/sparring_brain.gd` | 脚本陶练机（不是 AI） |
| `scripts/ui/combat_hud.gd` | 战斗 HUD |
| `scripts/debug/combat_autopilot.gd` | 真实渲染下的战斗演示 |
| `tests/check_scripts.gd` | 在完整工程环境（含 autoload）下编译全部脚本，有错误时立即失败 |

## 设计决策（续）

- **D-15 运动修正接口。** 突进类招式不直接写速度，而是由 `MovementModifier` 设置 `forced = true` 和 `forced_velocity`，MechMotor 仍是唯一写速度的地方，照常碰撞、受上升上限约束。T09 的静态检查覆盖战斗层的 3 个文件。
- **D-16 判定方式。** 近战在攻击活动段内每帧做一次 BoxShape 扫掠，只查询受击判定区（Hurtbox，物理层 5），每个目标在一次攻击中只结算一次。弹丸每帧做射线扫掠，能检测判定区，不会穿透。
- **D-17 结算顺序：权限 → 招架 → 格挡 → 命中。** 招架和格挡都只覆盖正面 120°。可招架的类型只有近战和弹丸；格挡对抓取以外的攻击都有效。
- **D-18 顿帧是个体级的。** 只冻结当事双方（MechMotor 跳过物理更新，战斗计时暂停）；弹丸命中只冻结受害者；不修改 `Engine.time_scale`。
- **D-19 硬控递减共享同一个计数池**（硬直、失衡、破防都计入）：4 s 窗口内第 n 次硬控时长 ×0.7ⁿ，第 4 次起免疫 1.5 s。目的是在多人围攻中防止永久控制。
- **D-20 折射时转移弹丸归属。** 弹丸飞回原发射者，伤害权限按新归属者判断，因此乱斗和联盟模式共用同一套代码，不需要按模式写分支。
- **D-21 大招解锁前按下的 V 不进入缓冲**，避免 HP 跌破阈值的那一刻自动发动。格挡中可以发动大招。
- **D-22 陶练机不是 AI。** 它是固定循环的脚本，没有感知、导航和决策（这些属于阶段 4），只用来提供可重复的对练对象。
- **D-23 程序合成占位音效。** 运行时用正弦波和滤波噪声生成，不引入外部文件，不存在许可证问题，阶段 7 替换。
