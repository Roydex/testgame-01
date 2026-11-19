# 机动参数表（MechMovementProfile / CameraRig）

> 状态：**全部为原型参数，待测试**（AGENT.md：未经实测不得宣称已平衡）。
> 数据位置：`resources/profiles/*.tres`（机体）与 `scripts/camera/camera_rig.gd` 的 `@export`（镜头）。
> 运行时按 **F2** 可在 5 套配置间切换，对比手感。

## 1. 机体配置

粗体 = 该机体覆盖了基础值；未加粗 = 沿用 `Base`（即 AGENT.md §10.2 规格初值）。

| 参数 | Base（规格初值） | 01 PALE SERAPH | 02 HELLFANG | 03 VERDANT ARK | 04 AZURE ORACLE |
|---|---|---|---|---|---|
| `ground_max_speed` | 14.0 | **16.0** | **13.0** | **10.0** | **12.0** |
| `ground_accel` | 50.0 | **70.0** | **42.0** | **30.0** | **40.0** |
| `ground_decel` | 60.0 | **75.0** | **45.0** | **55.0** | 60.0 |
| `ground_turn_grip` | 55.0 | **75.0** | **40.0** | **45.0** | **45.0** |
| `turn_speed_deg` | 720.0 | **900.0** | **540.0** | **400.0** | **600.0** |
| `overspeed_decel` | 30.0 | 30.0 | 30.0 | 30.0 | 30.0 |
| `ground_dash_speed` | 30.0 | **34.0** | **36.0** | **24.0** | 30.0 |
| `ground_dash_duration` | 0.32 | **0.28** | **0.34** | **0.36** | 0.32 |
| `ground_dash_cost` | 18.0 | 18.0 | 18.0 | 18.0 | 18.0 |
| `dash_cooldown` | 0.18 | **0.12** | **0.25** | 0.18 | 0.18 |
| `jump_velocity` | 9.0 | 9.0 | 9.0 | 9.0 | 9.0 |
| `takeoff_time` | 0.14 | 0.14 | 0.14 | 0.14 | 0.14 |
| `max_ascent_height` | 10.0 | 10.0 | 10.0 | 10.0 | 10.0 |
| `air_max_speed` | 13.0 | **15.0** | **12.0** | **10.0** | **14.0** |
| `air_accel` | 24.0 | **36.0** | **14.0** | **18.0** | **26.0** |
| `air_decel` | 10.0 | **14.0** | **6.0** | **20.0** | **16.0** |
| `air_turn_grip` | 18.0 | **34.0** | **8.0** | **22.0** | **20.0** |
| `exhausted_air_control` | 0.35 | 0.35 | 0.35 | 0.35 | 0.35 |
| `air_dash_speed` | 32.0 | **36.0** | **40.0** | **26.0** | **30.0** |
| `air_dash_duration` | 0.3 | **0.26** | **0.32** | 0.3 | 0.3 |
| `air_dash_cost` | 28.0 | 28.0 | 28.0 | 28.0 | 28.0 |
| `air_dash_steer_deg` | 90.0 | **160.0** | **45.0** | **60.0** | **80.0** |
| `ascend_speed` | 9.0 | **10.0** | **13.0** | **7.0** | **8.5** |
| `ascend_accel` | 30.0 | 30.0 | **45.0** | **22.0** | 30.0 |
| `descend_speed` | 14.0 | 14.0 | 14.0 | 14.0 | 14.0 |
| `descend_accel` | 40.0 | 40.0 | 40.0 | 40.0 | 40.0 |
| `hover_brake` | 25.0 | 25.0 | 25.0 | **40.0** | **35.0** |
| `max_en` | 100.0 | 100.0 | 100.0 | **110.0** | 100.0 |
| `hover_cost_per_sec` | 20.0 | 20.0 | **27.0** | **14.0** | **16.0** |
| `ascend_cost_per_sec` | 28.0 | 28.0 | **32.0** | **24.0** | 28.0 |
| `ground_regen_per_sec` | 22.0 | 22.0 | 22.0 | 22.0 | 22.0 |
| `regen_delay` | 0.8 | 0.8 | 0.8 | 0.8 | 0.8 |
| `air_regen_per_sec` | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| `gravity` | 24.0 | **22.0** | **28.0** | **26.0** | **23.0** |
| `max_fall_speed` | 40.0 | 40.0 | 40.0 | 40.0 | 40.0 |
| `landing_recovery` | 0.08 | 0.08 | 0.08 | 0.08 | 0.08 |
| `hard_landing_speed` | 20.0 | 20.0 | 20.0 | 20.0 | 20.0 |
| `hard_landing_recovery` | 0.3 | 0.3 | **0.4** | 0.3 | 0.3 |
| `landing_speed_mult` | 0.45 | 0.45 | 0.45 | 0.45 | 0.45 |

### 参数含义

| 参数 | 单位 | 含义 |
|---|---|---|
| `ground_max_speed` / `air_max_speed` | m/s | 地面 / 空中水平最高速度 |
| `ground_accel` / `air_accel` | m/s² | 沿输入方向的加速度 |
| `ground_decel` / `air_decel` | m/s² | 无输入时的减速度 |
| `ground_turn_grip` / `air_turn_grip` | m/s² | 变向时横向速度的消除速率；**越低惯性越大（漂移感）**，是 M02 机体差异的主要来源 |
| `turn_speed_deg` | °/s | 机体朝向旋转速度（锁定时朝向目标，否则朝向移动输入） |
| `overspeed_decel` | m/s² | 冲刺后超出最高速部分的衰减（空中为其 50%） |
| `*_dash_speed` / `*_dash_duration` / `*_dash_cost` | m/s, s, EN | 地面 / 空中冲刺速度、持续时间、EN 消耗 |
| `air_dash_steer_deg` | °/s | 空中冲刺过程中可修正方向的速率 |
| `dash_cooldown` | s | 两次冲刺最小间隔 |
| `jump_velocity` / `takeoff_time` | m/s, s | 起跳初速；起跳后多久才允许推进 |
| `max_ascent_height` | m | 推进可达高度 = 起飞点 + 该值（另受地图绝对天花板约束） |
| `ascend_speed` / `ascend_accel` | m/s, m/s² | 主动上升 |
| `descend_speed` / `descend_accel` | m/s, m/s² | 受控下降速度上限（有 EN 时；不耗 EN） |
| `hover_brake` | m/s² | 悬停时垂直速度归零的制动；也用于接近上升上限时的减速 |
| `hover_cost_per_sec` / `ascend_cost_per_sec` | EN/s | 悬停 / 上升消耗 |
| `ground_regen_per_sec` / `regen_delay` | EN/s, s | 地面恢复速率；最后一次消耗**或着陆**后的恢复延迟 |
| `air_regen_per_sec` | EN/s | 空中恢复（规格：0） |
| `exhausted_air_control` | 0–1 | EN 耗尽后空中方向控制倍率 |
| `gravity` / `max_fall_speed` | m/s², m/s | 重力 / 终端速度 |
| `landing_recovery` / `hard_landing_speed` / `hard_landing_recovery` | s, m/s, s | 普通着陆恢复；超过阈值冲击速度为硬着陆 |
| `landing_speed_mult` | 0–1 | 着陆恢复期间的水平速度倍率（**不会完全锁死操作**） |

## 2. 实测派生数据（来自 `tests/logs/test_results.log`）

| 指标 | Base | Seraph | Hellfang | Ark | Oracle |
|---|---|---|---|---|---|
| 地面 0→95% 极速 | 0.27 s | 0.23 s | 0.30 s | 0.32 s | 0.30 s |
| 地面 90° 变向（速度方向） | 0.23 s | 0.18 s | 0.28 s | 0.20 s | 0.23 s |
| 地面急停 | 0.23 s | 0.22 s | 0.28 s | 0.18 s | 0.20 s |
| 空中全速反向：速度过零 | 0.38 s | 0.32 s | **0.62 s** | 0.27 s | 0.35 s |
| 空中全速反向：达到 90% 反向速度 | 0.88 s | 0.68 s | **1.37 s** | 0.77 s | 0.82 s |
| 满 EN 动力滞空（0 次空中冲刺） | 5.05 s | 5.05 s | 3.82 s | 7.82 s | 6.20 s |
| 连续 2 次空中冲刺后剩余悬停 | 46% | 47% | 47% | 50% | 44% |
| 按住上升直至 EN 耗尽 → 着陆 | 5.65 s | 5.72 s | 4.57 s | 7.98 s | 6.52 s |

## 3. 能量规则（实现说明）

- 地面冲刺 18 EN、空中冲刺 28 EN、悬停 20 EN/s、上升 28 EN/s、地面恢复 22 EN/s、恢复延迟 0.8 s（Base）。
- **空中不恢复 EN**；EN 不足冲刺消耗时无法冲刺。
- EN 为 0：不能悬停、不能上升，**主动下降键也失效**（变为纯重力下落，可能触发硬着陆）；保留 `exhausted_air_control` 比例的水平控制。
- 恢复延迟在**最后一次消耗**和**着陆**时都会重置（默认决策，见 ARCHITECTURE.md D-05）。
- 上升接近上限时按 `hover_brake` 提前减速，不会冲过 `起飞点 + 10 m`（修复记录见 KNOWN_ISSUES.md）。

## 4. 镜头参数（CameraRig 默认值）

| 参数 | 值 | 说明 |
|---|---|---|
| `base_fov` / `dash_fov` | 70° / 78° | 冲刺时 FOV，按速度插值 |
| `distance_presets` / `distance_preset_index` | 7.5 / **10** / 13 m，默认中档 | 跟随距离三档（近 / 中 / 远），按 `Z` 循环切换，以 `distance_change_sharpness` = 5 平滑过渡 |
| `focus_height` / `shoulder_offset` | 3.2 m / 1.2 m | 注视点高度、越肩偏移 |
| `follow_sharpness_h` / `follow_sharpness_v` | 22 / 7 (1/s) | 水平 / 垂直跟随锐度；垂直更柔和以平滑起降 |
| `speed_pullback` | 1.2 m | 冲刺时镜头拉远 |
| `mouse_sensitivity` | 0.0025 rad/px | 自由视角灵敏度 |
| `pitch_min_deg` / `pitch_max_deg` | -70° / 55° | 自由视角俯仰限制 |
| `lock_max_turn_deg` | 200°/s | **所有自动旋转的速率上限**（锁定、切换、解除） |
| `lock_sharpness` | 5 (1/s) | 锁定跟随平滑 |
| `lock_aim_weight` | 0.45 | 视线在“玩家→目标”之间的角度插值 |
| `lock_player_max_angle_deg` | 26° | 玩家胸口始终保持在画面中心该角度内 |
| `lock_orbit_pitch_min/max_deg` | -35° / 8° | 锁定时镜头位置俯仰（避免仰视高空目标时镜头钻地） |
| `lock_height_distance_factor` / `lock_max_extra_distance` | 0.18 m/m / 5 m | 高度差越大镜头越远 |
| `lock_manual_yaw_deg` / `lock_manual_pitch_deg` | ±25° / ±15° | 锁定时鼠标可做的偏移，0.8 s 后回正 |
| `collision_radius` | 0.35 m | 遮挡球形扫掠半径 |
| `min_comfort_distance` / `raise_height` | 2.8 m / 4 m | 被挤近时尝试抬高（锁定时还尝试左右 ±50°/±90°）的备选位置 |
| `fade_start_distance` / `fade_end_distance` | 3.0 m / 1.2 m | 镜头过近时机体淡出 |

## 5. 锁定参数（TargetingSystem）

| 参数 | 值 |
|---|---|
| `lock_range` / `lose_range` | 150 m / 175 m |
| `lose_los_time` | 3 s（被遮挡超过则解除） |
| `acquire_cone_deg` | 75°（优先锁定镜头前方） |
| `auto_switch_on_destroy` | 开（目标被摧毁自动切换到最近目标） |
