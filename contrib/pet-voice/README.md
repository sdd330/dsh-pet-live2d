# pet-voice —— 让桌宠真的说话

插件本身只有**气泡台词**，没有声音。这里补一条音轨：订阅插件已经推出来的会话相位，
在对应时刻播放预制语音。

```
DSH 宿主 ──SSE──▶ pet-voice.py ──▶ afplay ──▶ 扬声器
   /api/live2d-pet/events     ~/.dsh/pets/<pet>/voice/*.mp3
```

## 分工：它只管相位

互动语音（点击 / 摸头 / 摸尾 / 绕晕）由**插件本体**在页面里播——那些事件只发生在
浏览器，宿主看不到。这个旁挂守护只负责**相位台词与问候**（`phase-*.mp3`、`greet-*.mp3`），
并且默认收窄到 `done` / `failed`。

两边都靠 `voice/` 目录，但不会重复：插件会跳过 `lines.phase` 与 `lines.greet` 里的文本。

## 为什么是"旁挂"而不是改插件

- 插件装在 `~/.dsh/profiles/<profile>/node_modules/` 下，**升级会被覆盖**；
- 插件已经把相位通过 `GET /api/live2d-pet/events` 推出去了，消费这条流就够了，
  一行插件代码都不用动；
- 不想要声音时 `--off` 即可，插件行为完全不受影响。

## 三个文件

| 文件 | 作用 |
|---|---|
| `pet-voice.py` | 守护进程：订阅 SSE，按相位播 `voice/phase-<相位>.mp3` |
| `pet-voice-gen.py` | 用 MiniMax（[`mmx`](https://www.npmjs.com/package/mmx-cli)）把 `pet.json` 里的台词批量生成 mp3 |
| `pet-voice-ctl.sh` | 控制：开关 / 换宠物 / 换音色 / 重生成 |
| `pet-status.sh` | 只读体检：端口、可见宠物、语音覆盖、守护状态 |

## 装

```bash
cp contrib/pet-voice/*.py contrib/pet-voice/*.sh ~/.dsh/
chmod +x ~/.dsh/pet-voice-ctl.sh
~/.dsh/pet-voice-ctl.sh --on
```

`--on` 会在 `~/Library/LaunchAgents/com.dsh.pet-voice.plist` **自动生成**守护配置
（`RunAtLoad` + `KeepAlive`：开机自启，进程挂了自动拉起），不需要手写 plist。

日志在 `/tmp/pet-voice.log`。默认**安静**（只在出错时输出），要看每个相位播了什么，
在 plist 的 `EnvironmentVariables` 里加一条 `<key>PET_DEBUG</key><string>1</string>` 后
`--on` 重启即可。

**Linux**：把 `--on` 那段换成 systemd user unit，并把 `pet-voice.py` 的 `play()` 从
`afplay` 换成 `paplay` / `aplay`。

## 用

```bash
~/.dsh/pet-voice-ctl.sh --off                    # 关掉
~/.dsh/pet-voice-ctl.sh --on                     # 打开
~/.dsh/pet-voice-ctl.sh --pet natori             # 换台词来源
~/.dsh/pet-voice-ctl.sh --list                   # 列出可用的 MiniMax 中文音色
~/.dsh/pet-voice-ctl.sh --voice female-shaonv    # 换音色并全部重新生成
```

## 体检

```bash
bash ~/.dsh/pet-status.sh
```

```
DSH
  端口: 62455
  可见宠物: 3 只
    haru     「春 Haru」 动作  6  表情  8  装扮项  8  语音 25
    mao      「小舞 Mao」 动作  8  表情  8  装扮项  8  语音 28
配音
  守护: running
  宠物: mao
  相位: done,failed（默认）
```

## 生成语音

**语音一律用 MiniMax（`mmx`）生成，不要用 macOS `say`。** `say` 的中文音色是十几年前的
引擎，机械感很重；`mmx speech synthesize` 是真人级音色。生成器在找不到 `mmx` 时直接报错，
不提供 `say` 兜底。

```bash
python3 ~/.dsh/pet-voice-gen.py --pet mao --voice female-shaonv
python3 ~/.dsh/pet-voice-gen.py --pet mao --voice "Chinese (Mandarin)_Crisp_Girl" --force
```

产物命名规则（`pet-voice.py` 按这个找文件）：

```
greet-1..N.mp3   click-1..N.mp3   pat-1..N.mp3   tail/spin/reset/loadFailed-N.mp3
phase-thinking.mp3  phase-tool.mp3  phase-waiting.mp3  phase-asking.mp3
phase-helper.mp3    phase-queued.mp3  phase-done.mp3   phase-failed.mp3
```

生成是幂等的：已存在的文件跳过，`--force` 强制重生成。默认每条之间停 1.5 秒并退避重试
（`--delay` / `--retries` 可调）——MiniMax 有 RPM 限制，连着打会返回
`rate limit exceeded(RPM)`，一批里失败大半。

## 行为细节

- **默认只播这一轮的结果**：`done` / `failed`。其余全部静音 —— 一轮里
  `thinking↔tool` 会反复切换，`waiting` / `asking` 也会被审批和提问连续触发，每次都念
  就成了背景噪音。想加回来：`PET_PHASES=waiting,asking,done,failed`。
- **端口自动发现**：DSH 每次重启端口都会变，脚本用 `lsof` 找 DeepSeek 进程的监听端口
  再探测插件接口；流断了自动重连（日志里能看到 `stream dropped` → `connected`）。
- **不排队**：新的一句优先，播放中的旧句会被 `terminate`。
- 没有对应音频就**保持安静**——不会退回到机器的 `say`（音色不行，明确不用）。
