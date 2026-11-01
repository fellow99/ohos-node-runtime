#!/usr/bin/env node
/**
 * publish-har.mjs — 为指定 Node 版本出 runtime HAR（不含 publish，只到 verify-har）。
 * 用法: node scripts/publish-har.mjs <node_version>
 *   例: node scripts/publish-har.mjs 22.23.4
 * 会: 切 lock.active → 同步 oh-package/Index.ets → provision(投放引擎+修正libc++) → assembleHar → verify-har
 */
import { readFileSync, writeFileSync, copyFileSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const REPO = resolve(dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const version = process.argv[2];
if (!version) { console.error('用法: node scripts/publish-har.mjs <node_version>'); process.exit(2); }

const SYSNODE = process.execPath;
const DS = 'D:/oh-workspace/deveco-studio-6';
const env = { ...process.env, DEVECO_SDK_HOME: 'D:\\oh-workspace\\deveco-studio-6\\sdk' };

const lockPath = join(REPO, 'runtime.lock.json');
const lock = JSON.parse(readFileSync(lockPath, 'utf8'));
const entry = (lock.runtimes ?? []).find(r => r.node === `v${version}`);
if (!entry) { console.error(`lock 里没有 v${version}`); process.exit(2); }

console.log(`\n=== 发布 ${version} (ABI ${entry.nodeModuleVersion}) ===`);

// 1) 切 active
lock.active = { node: `v${version}`, abi: entry.abi };
writeFileSync(lockPath, JSON.stringify(lock, null, 2) + '\n', 'utf8');
console.log(`lock.active → v${version}`);

// 2) 同步 oh-package.json5 version + description
const pkgPath = join(REPO, 'runtime-har/oh-package.json5');
let pkg = readFileSync(pkgPath, 'utf8');
pkg = pkg.replace(/"version":\s*"[^"]*"/, `"version": "${version}"`);
pkg = pkg.replace(/Node v[\d.]+ 的/, `Node v${version} 的`);
if (entry.nodeModuleVersion === 147) {
  pkg = pkg.replace(/（libnode\.so）/, `（libnode.so，ABI ${entry.nodeModuleVersion}）`);
}
writeFileSync(pkgPath, pkg, 'utf8');

// 3) 同步 Index.ets
const idxPath = join(REPO, 'runtime-har/Index.ets');
let idx = readFileSync(idxPath, 'utf8');
idx = idx.replace(/NODE_VERSION: string = '[^']*'/, `NODE_VERSION: string = '${version}'`);
idx = idx.replace(/NODE_MODULE_VERSION: number = \d+/, `NODE_MODULE_VERSION: number = ${entry.nodeModuleVersion}`);
idx = idx.replace(/LIB_SHA256: string = '[^']*'/, `LIB_SHA256: string = '${entry.sha256}'`);
idx = idx.replace(/LIB_SIZE: number = \d+/, `LIB_SIZE: number = ${entry.size}`);
idx = idx.replace(/node-v[\d.]+ \/ arm64-v8a \/ abi\d+/, `node-v${version} / arm64-v8a / abi${entry.nodeModuleVersion}`);
writeFileSync(idxPath, idx, 'utf8');

// 4) provision（投放引擎 + SDK libc++，然后用 CI 修正版覆盖）
const engineSrc = join(REPO, 'runtime/node-v' + version, 'libnode-arm64.so');
const libcxxSrc = join(REPO, 'runtime/node-v' + version, 'libc++_shared.so');
const outDir = join(REPO, 'runtime-har/libs/arm64-v8a');
execFileSync(SYSNODE, [
  'tools/provision.mjs',
  '--node', `v${version}`, '--abi', entry.abi,
  '--sdk', DS + '/sdk/default/openharmony',
  '--from', engineSrc,
  '--out', 'runtime-har/libs/arm64-v8a', '--force'
], { cwd: REPO, stdio: 'inherit', env });

// 覆盖为 CI 修正版 libc++
if (existsSync(libcxxSrc)) {
  copyFileSync(libcxxSrc, join(outDir, 'libc++_shared.so'));
  console.log('libc++ → CI 修正版 (aarch64)');
}

// 5) assembleHar
execFileSync(SYSNODE, [
  DS + '/tools/hvigor/bin/hvigorw.js',
  '--mode', 'module', '-p', 'module=runtimehar@default', '-p', 'buildMode=release',
  'assembleHar', '--no-daemon'
], { cwd: REPO, stdio: 'inherit', env });

// 6) verify-har
const harPath = join(REPO, 'runtime-har/build/default/outputs/default/runtimehar.har');
execFileSync(SYSNODE, ['tools/verify-har.mjs', harPath], { cwd: REPO, stdio: 'inherit', env });

console.log(`\n✓ ${version} HAR 已就绪: ${harPath}`);
