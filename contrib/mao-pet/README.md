# 小舞 Mao —— 一只官方的、真的会动的桌宠

把 Live2D 官方示例角色 **Mao（小舞）** 接成 DSH 桌宠，并补齐插件要的三样东西：

| 补的东西 | 为什么原本不行 |
|---|---|
| **相位 → 动作映射** | 插件内置相位表是照 DS鲸鱼娘写的（`done:"BubbleGum"`、`failed:"SprayWater"`），Mao 没有这两个组，于是完成任务、出错时**什么都不播** |
| **中文标签** | 中文界面下插件**不加载 `locale/` 覆盖层**（`PET_LOCALE === "zh"` 直接返回 null），所以中文名只能写进 `catalog.json` 的 `label` |
| **台词 + 语音** | 官方模型只带模型，没有气泡台词，也没有配音 |

## 装

```bash
cd contrib/mao-pet
./install.sh                          # 从 GitHub 拉官方模型
./install.sh /path/to/Mao             # 或用你本地已有的 Mao 目录
```

然后**刷新 DSH 页面**，右键桌宠 → 标题栏下拉选「小舞 Mao」。

装完的目录长这样：

```
~/.dsh/pets/mao/
├── Mao.model3.json       # setup.mjs 改写过：Idle + react-1..6
├── Mao.moc3 / textures/ / motions/ / expressions/   # 官方模型
├── pet.json              # 相位映射 + 表情槽 + 台词
├── catalog.json          # 中文标签（待机 / 互动 一~六 / 表情 1~8）
├── locale/en.json        # 英文界面的覆盖层
└── voice/*.mp3           # 28 条 MiniMax 语音
```

## 装了之后的行为

| 会话状态 | 动作 | 说什么 |
|---|---|---|
| 待机 / 思考 / 跑工具 / 等你确认 | `Idle` | *（静音）* |
| **回合完成** | **`react-4`（举手）** | 「搞定！」 |
| **出错** | **`react-2`** | 「呜…出错了」 |

## 语音分两条腿

| 触发 | 谁播 | 覆盖 |
|---|---|---|
| **互动**：点击 / 摸头 / 摸尾巴 / 绕晕 / 归位 | **插件本体**（本分支对 `dsh-live2d-pet` 的改动） | 点她、绕她都会出声 |
| **相位**：回合完成 / 出错 | [`../pet-voice/`](../pet-voice/README.md) 的旁挂守护 | 默认只播 `done` / `failed` |

之所以分开：互动事件只发生在浏览器里，宿主的旁挂守护看不到；相位又不想让页面自己播
（高频状态会吵，而且会与守护重复）。插件用 `catalog.voice` 把**台词文本**映射到
`voice/<file>`，页面在 `say()` 里按文本查表播放；守护只负责 `phase-*.mp3` 与问候。

> ⚠️ 互动语音需要**本分支的插件构建**（`dsh-live2d-pet/lib/{index,client}.js` 的改动），
> npm 上的 3.6.0 还没有这个能力。装上本分支的 `dsh-live2d-pet/` 目录才会响。

「抬手 / 歪头 / 扶帽 / 举手 / 挥手 / 张望」在右键面板的**动作**页签里都能单独点播；「装扮」页签里是 8 个表情。

## 动作标签是推断的

拆出来的 6 个互动动作，官方模型只给了 `mtn_02` / `special_01` 这种文件名，没有语义。
标签是根据**各自驱动参数的特征**推断的：

| 组 | 主要变化的参数 | 起的名字 |
|---|---|---|
| `react-1` | 双臂对称小幅抬起（-4→14）+ 抬头 | 抬手 |
| `react-2` | 歪头 ±15 + 身体侧摆 ±10 + 单臂下垂 | 歪头 |
| `react-3` | 左臂大幅（-30→19）+ `HatForm` 0→21 | 扶帽 |
| `react-4` | 右臂高举（-22→30）+ 抬头 | 举手 |
| `react-5` | 右臂大幅 + 抬头 | 挥手 |
| `react-6` | 大幅左右转头（-25→18）+ 右臂 | 张望 |

觉得不准就改 `catalog.json` 里对应的 `label`（只影响显示名），
或者改 `pet.json` 的 `live2d.motions` 把 `done` / `failed` 指到别的组。

## 语音怎么来的

**全部由 MiniMax（[`mmx-cli`](https://www.npmjs.com/package/mmx-cli)）生成，不用 macOS 的 `say`** ——
后者是十几年前的老引擎，中文机械感很重，拿来当桌宠配音不合适。

| 项 | 值 |
|---|---|
| 模型 | `speech-2.8-hd` |
| 音色 | `Chinese (Mandarin)_Soft_Girl`（软妹，偏娇羞） |
| 条数 | 42 |
| 记录 | [`voice.json`](voice.json) |

```bash
# 重新生成（幂等；--force 强制重来）
python3 ../pet-voice/pet-voice-gen.py --pet mao --voice "Chinese (Mandarin)_Soft_Girl"
```

换音色：`../pet-voice/pet-voice-ctl.sh --voice "Chinese (Mandarin)_Crisp_Girl"`，会重新生成并重启守护。
别的角色可以各配各的（这套里 Haru 用 `Chinese (Mandarin)_Warm_Girl`，Natori 用 `female-yujie`）。

> 台词与音频**按位置对应**（`lines.greet[i]` ↔ `greet-(i+1).mp3`）。改了台词顺序就要整批重生成，
> 只补增量会张冠李戴。

## 为什么没有把模型一起提交

Live2D《[无偿提供素材使用授权协议](https://www.live2d.com/eula/live2d-free-material-license-agreement_cn.html)》
**4.1.1 禁止再分发**：「您不得将部分或全部本素材转发至第三方」。

所以本目录**只放配置和语音**，`.moc3` / 贴图 / 动作一律由 `install.sh` 在**使用者本机**从
Live2D 官方仓库 [Live2D/CubismWebSamples](https://github.com/Live2D/CubismWebSamples) 拉取。
剧本台词是本仓库原创，语音由 MiniMax TTS 生成。

使用该模型请自行遵守 Live2D 的授权条件（个人及年收 < 1000 万日元的小规模事业者可用于
营利/非营利目的；企业用户限于内部与监修用途）。详见
[Live2D Cubism 示例数据利用条件](https://www.live2d.com/eula/live2d-sample-model-terms_cn.html)。

## 换成别的角色

`Haru`（春）、`Natori`（名取）同样适用：把 `install.sh` 里的 `Mao` 换成目录名即可，
`setup.mjs` 会把它们的 `TapBody` 按同样规则拆成 `react-N`。
