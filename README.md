# 机甲乱斗 Mech Brawl — Ground-Air Hybrid 机动原型

Godot 4.7.2 + GDScript。- 阶段 2a 机动 / 能量 / 镜头原型：**PASS**（M03/M07/M08/M09 DEFERRED，已绑定到后续阶段）。
- 阶段 2b 单机体战斗原型（01 白祷）：**AWAITING_USER_ACCEPTANCE**。
项目规范见 [AGENT.md](AGENT.md)，验收结果见 [docs/TEST_MATRIX.md](docs/TEST_MATRIX.md)。

## 运行

```bash
../engine/Godot.app/Contents/MacOS/Godot --path .
```

也可以用 Godot 编辑器打开本目录后按 F5，主场景为 `scenes/test/graybox_test.tscn`。

## 操作说明

| 按键 | 功能 |
|---|---|
| 鼠标左键 | 捕获鼠标；`Esc` 释放 |
| 鼠标移动 | 转动视角（锁定时为有限偏移，自动回正） |
| `W A S D` | 移动（以镜头水平朝向为基准） |
| `Space` | 地面：跳跃；按住：推进上升（上限为起飞点 + 10 m）；空中松开：悬停（耗 EN） |
| `C` / `Ctrl` | 受控下降（有 EN 时生效） |
| `Shift` | 冲刺：地面冲刺 18 EN / 空中冲刺 28 EN |
| `Q` / 鼠标中键 | 锁定 / 解除锁定 |
| `E` / `R` / 滚轮 | 切换锁定目标（右 / 左） |
| `Z` | 镜头距离：近 7.5 m / 中 10 m（默认） / 远 13 m 循环切换 |
| 左键 | 光矛连段（刺 → 横扫 → 贯）。鼠标未捕获时，第一次点击只捕获鼠标 |
| 右键（按住） | 折射镜盾：格挡，覆盖正面 120°，消耗 EN |
| `F` | 折射镜盾：招架，窗口 0.15 s；近战招架使对方失衡，弹丸招架会折射回去 |
| `X` | 瞬时突进斩（20 EN，冷却 2.5 s，可以打低空目标）；审判状态下变为终审之矛 |
| `V` | 大招「圣骸回响 · 冠冕补完」（HP ≤ 30% 时解锁，每局 1 次） |
| `F1` | 显示 / 隐藏调试面板 |
| `F2` | 切换机动配置（Base → Seraph → Hellfang → Ark → Oracle） |
| `F3` | 测试硬直（STAGGER + 击退） |
| `F4` | 测试战斗动作（ACTION：减速、禁止冲刺） |
| `F5` | 回到出生点 |
| `F6` | 开 / 关测试射击（T1、T3 闪红后开火，用于空中规避测试） |
| `K` | 击毁当前锁定目标（测试目标丢失和自动切换） |
| `F7` | 重开 |
| `F8` | 切换两台陶练机的阵营：互相敌对（乱斗）/ 同阵营（联盟） |
| `F9` | 切换近战陶练机的模式：近战 / 远程 / 静止 / 只格挡 / 定时招架 |
| `F10` | 把自己的 HP 降到 29%（用于测试大招） |

调试面板显示：运动状态、战斗状态、速度向量（3D 绿线）、EN、离地高度、上升上限、滞空时间、碰撞状态、锁定目标与高度差、镜头 FOV 和遮挡、生效中的修正器、受击 / 规避统计、FPS。屏幕边缘的红色三角为离屏敌人提示（▲▼ 表示目标在上方或下方）。

## 灰盒关卡

灰盒关卡由 `scripts/level/graybox_builder.gd` 生成，**不是**正式地图。包含：
- 平地。
- 1 / 2 / 4 / 7 / 10 m 的台阶，以及一条 4 m 坡道。
- 8 m 中台 → 两座 16 m 高塔，塔间有连接桥。
- 1 m 厚墙和 0.3 m 薄墙。
- 两层楼板结构（8 m 与 16 m）。
- 3.2 m 宽的有顶狭窄通道。
- 40 m 飞行天花板（淡红色平面）和四周边界墙。
- 6 个测试靶：静止低空、26 m 高空、±12 m 上下浮动、环绕飞行、地面、塔顶。

## 自动化测试

```bash
tests/run_tests.sh
```

无头运行，固定 60 Hz 步长，共 24 项，用时约 1 分钟。可加 `--only=T05` 只跑单项。日志写入 `tests/logs/test_results.log`，退出码 0 表示全部通过。

真实渲染演示（自动截图到 `docs/screenshots/`，并输出帧率统计），机动演示：

```bash
../engine/Godot.app/Contents/MacOS/Godot --path . --resolution 1920x1080 -- --autopilot
```

战斗演示：

```bash
../engine/Godot.app/Contents/MacOS/Godot --path . --resolution 1920x1080 -- --combat-demo
```

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：分层、设计决策、碰撞层。
- [docs/MOVEMENT_PARAMETERS.md](docs/MOVEMENT_PARAMETERS.md)：机动参数表和实测数据。
- [docs/COMBAT_PARAMETERS.md](docs/COMBAT_PARAMETERS.md)：战斗参数表（招式、防御、大招、反馈）。
- [docs/MECH_DESIGN.md](docs/MECH_DESIGN.md)：白祷的设定、武装、招架规则、大招与混战规则。
- [docs/TEST_MATRIX.md](docs/TEST_MATRIX.md)：M01–M10 验收矩阵和人工验收清单。
- [docs/ROADMAP.md](docs/ROADMAP.md)、[docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)、[docs/BALANCE_REPORT.md](docs/BALANCE_REPORT.md)。
