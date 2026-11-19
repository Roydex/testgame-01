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
- **D-24 程序化动作层。** MechVisual 搭了一套简单骨架（髋、腿、躯干、双臂、光矛、镜盾），按“当前招式 + 出招进度”从关键姿势插值得到姿势；顿帧期间冻结姿势。它只读取战斗和运动状态，不影响任何判定，属于阶段 7 之前的占位动作。
- **D-25 新增 `CombatEvents.attack_active` 事件。** 攻击进入活动段时发出，用于挥舞音效和光矛拖尾，使声画与判定时刻对齐，而不是在前摇一开始就播放。
- **D-26 练习模式（默认开启，按 F12 切换）。** 由场景统一设置：HP 下限为 1；陪练机受伤 4 s 后自动回血；大招不限次数（`UltimateSystem.unlimited_uses`）；陪练机同阵营，使用 TRAINING 节奏。实战模式保留全部规则。练习相关的分支全部集中在场景层，战斗核心不知道“练习”的存在。
- **D-27 近距离锁定取景。** 目标水平距离小于 8 m 时，镜头逐渐偏到肩侧（3.2 m）并抬高 1.8 m，避免目标和出招动作被玩家自己的机体挡住。
- **D-28 UiFont。** 运行时从系统字体中挑选第一个确实包含简体字形的字体（macOS 上 PingFang.ttc 的第一个字体是 PingFang HK，缺“远”等字，因此会选中 Hiragino Sans GB），应用到所有 HUD 和 Label3D。项目中不放入任何字体文件。

---

# 阶段 3a：四机体差异化（武装与资源）

```
 MechCommand（新增 attack_held / skill_held）
        ▼
 CombatStateMachine ── 短按 / 长按判定（hold_threshold）、CHARGE 状态（蓄力攻击）、F = 招架或防御动作
   │  在固定接缝调用 ──▶ MechKit（HeatKit / DeployKit / MarkKit）：can_start、outgoing_mult、incoming_mult、
   │                     guard_ratio_add、blocks_actions、on_attack_started / active / finished、on_hit_dealt、on_guarded
   │  有效段开始时按 delivery 分发：
   │    HITBOX（扫掠） / PROJECTILE（Projectile，可多弹、追踪、可击落、爆炸） / GRAPPLE（Grapple）
   │    ORBITAL（OrbitalStrike） / DEPLOY（Deployables → Turret / SlowZone） / SELF（排气、后跃）
   ▼
 DamageSystem.resolve()：can_damage → 无敌（EVADED）→ 招架 → 格挡 → 命中；命中后施加状态
   │  非机体受击体（炮台、导弹）：只结算伤害
   ▼
 StatusEffects（每台机体一个）：破甲 / 束缚 / 标记；移动影响合成一个 MovementModifier
```

| 文件 | 职责 |
|---|---|
| `scripts/combat/specs/*.gd` | 投送方式的数据：`ProjectileSpec`、`GrappleSpec`、`OrbitalSpec`、`DeploySpec`、`StatusEffectDefinition` |
| `scripts/combat/kits/*.gd` | 机体资源组件 `MechKit` 及其配置 `KitConfig`：`HeatKit` / `DeployKit` / `MarkKit` |
| `scripts/combat/status_effects.gd` | 计时状态效果 |
| `scripts/combat/entities/*.gd` | `Grapple`、`Turret`、`SlowZone`、`OrbitalStrike`、`AreaBlast`、`Deployables` |
| `scripts/level/skill_lab_scene.gd`、`scenes/test/skill_lab.tscn` | 技能测试场景 |
| `scripts/debug/skill_demo.gd` | 技能演示（截图 + P12 帧率） |
| `tests/phase3_tests.gd` | T28–T36 |
| `tests/balance_sim.gd` | 平衡模拟（DPS 探针 + 脚本 1v1） |

## 设计决策（续）

- **D-29 MechKit 接缝，而不是按机体分支。** 战斗状态机不认识任何具体机体，只在固定接缝调用 kit。没有 kit 的机体（白祷）使用中性的基类，所以 2b 的行为不变（T14–T27 保持通过）。
- **D-30 投送方式与伤害类型分开。** `attack_type` 决定招架、格挡规则（MELEE / PROJECTILE 可招架；BEAM / EXPLOSION 只能格挡；GRAB 都不行）；`delivery` 决定命中怎么产生。2b 的数据（`attack_type = PROJECTILE`、没有写 `delivery`）仍按弹丸发射（`get_delivery()` 兼容）。
- **D-31 短按 / 长按。** 有长按技能时，X 短按在松开时触发（因此有约 0.1 s 的延迟），按住 0.3 s 触发长按技能；没有长按技能时（白祷）仍是按下即触发。左键长按只在 kit 允许时（赤狱热量 ≥ 60）才进入判定，否则左键照常按下即出招。
- **D-32 蓄力是通用状态。** `CHARGE` 状态取代右键格挡（`charge_attack` 不为空时），蓄力开始时发出 telegraph 事件（瞄准激光就是预警），松开时按蓄力比例缩放伤害和弹速，达到阈值破防。
- **D-33 弹丸改为球形扫掠**（解决 K12）。每帧用 `cast_motion` 扫掠半径为 `projectile_radius` 的球体，再在接触点查询碰到了什么：世界几何体（掩体）就停下，受击判定区就结算，友军和已死目标直接穿过。
- **D-34 非机体受击体。** 炮台、导弹都有 `health`、`team_id`、`is_alive()` 和 `Hurtbox`。DamageSystem 对它们只结算伤害，没有招架、格挡和受击反应；敌对判断同样走 TeamRules，所以联盟的弹丸会穿过友方导弹。
- **D-35 所有新攻击都先检查视线。** 钩爪、炮台火力、爆炸、后跃推开都要求与目标之间没有世界几何体；轨道激光检查的是目标到天空的视线，所以顶棚能挡住它。放置部署物时，如果和放置点之间有墙，放置点会退到墙前。
- **D-36 状态不是硬控。** 束缚、破甲、标记都放在 StatusEffects 里，不进入硬控递减计数池；硬直、失衡、破防仍只由 CombatStateMachine 处理（D-19）。束缚只减速，不定身。
- **D-37 钩爪的位移是运动修正。** 拉近自己和拽下空中目标都通过带 `forced` 的 MovementModifier 实现，结束时用 0.05 s 低速收尾，避免冲过目标；钩爪节点被销毁时一定移除修正器。
- **D-38 苍藓资源按用户 2026-11-19 的要求改为“炮台位 + 冷却”**，取消孢核；已存在的炮台满 2 座时部署被拒绝（不顶掉旧炮台），这样资源状态更好读。
- **D-39 标记全局可见、所有苍穹共用。** 标记是目标身上的状态，任何苍穹都能消耗它（FFA 中两台苍穹会互相“偷”标记）。这是小歧义，采用了简单方案，阶段 4 可以改成按施加者区分。
- **D-40 陪练脚本的通用武装循环。** 有 kit 或长按技能的陪练机，按固定顺序循环“主攻击 → X 短按 → 主攻击 → X 长按 → 左键长按 / 蓄力”，并保持在机体的偏好距离。它仍然只是脚本（D-22），不是 AI。
