#!/usr/bin/env node
// 把官方 Mao 的 model3.json 改写成插件能按相位驱动的形状。
//
// 为什么必须改：插件的相位 → 动作是「组名 + 固定索引 0」（`playOnce(group, 0)`），
// 而官方模型把 6 个互动动作全塞在同一个 `TapBody` 组里。不拆的话 done / failed
// 只能播到 TapBody 的第 0 个，两个相位看起来一模一样。
//
// 拆分后：Idle（2 个待机）+ react-1..6（每个 1 个互动），
// 相位映射见 pet.json：done → react-4（举手），failed → react-2（歪头）。
//
// 用法: node setup.mjs <宠物目录>

import fs from 'node:fs'
import path from 'node:path'

const dir = process.argv[2]
if (!dir) {
  console.error('用法: node setup.mjs <宠物目录>')
  process.exit(1)
}

const file = fs.readdirSync(dir).find((name) => name.endsWith('.model3.json'))
if (!file) {
  console.error(`在 ${dir} 里找不到 *.model3.json`)
  process.exit(1)
}

const target = path.join(dir, file)
const model = JSON.parse(fs.readFileSync(target, 'utf8'))
const motions = model.FileReferences?.Motions ?? {}

if (!Array.isArray(motions.Idle) || motions.Idle.length === 0) {
  console.error('这个模型没有 Idle 组，不是预期的 Mao 模型')
  process.exit(1)
}

const tap = motions.TapBody ?? []
const next = { Idle: motions.Idle }
tap.forEach((entry, index) => { next[`react-${index + 1}`] = [entry] })
// 其它组原样保留（Mao 目前没有，留着以防模型更新）
for (const [group, list] of Object.entries(motions)) {
  if (group !== 'Idle' && group !== 'TapBody') next[group] = list
}
model.FileReferences.Motions = next

fs.writeFileSync(target, JSON.stringify(model, null, 2) + '\n')
console.log(`  ${file}: Idle ${next.Idle.length} 个 + react-1..${tap.length}`)
