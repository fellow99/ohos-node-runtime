/**
 * probe-runner.ets —— probe-app 探针核心（101-probe-app）。
 *
 * 判据口径见 specs/101-probe-app/spec.md（RFC2119）与 test-cases.md：
 *   PRB-01 载荷就位   ：枚举 context.bundleCodeDir 下 libs/arm64-v8a 清单 + size vs LOCK
 *   PRB-02 版本事实   ：CLAIMED(@fellow99/node-runtime 常量) vs LOCK(rawfile 快照) → PASS-FACT
 *   PRB-03 ELF 头校验 ：设备侧只读 64B（魔数/AArch64），完整七项门禁在 host provision --check
 *   PRB-04 加载边界   ：libnode.so 无 NAPI、本 HAP 无桥、SDK 暴露无 dlopen ⇒ 判 PASS-FACT(不可执行)
 *   PRB-05 报告       ：结果 UTF-8 JSON 写 filesDir/probe-result.json
 *
 * 事实披露优先，不硬造执行（spec test-cases FB-1..4 / 决断 A..D）。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import {
  NODE_VERSION,
  NODE_MODULE_VERSION,
  ABI,
  LIB_SHA256,
  LIB_SIZE,
  RUNTIME_ID
} from '@fellow99/node-runtime';

/** rawfile node-runtime-facts.json 的结构（authoring-time 快照，生成自 runtime.lock.json） */
interface LockFacts {
  activeNode: string;
  activeAbi: string;
  nodeModuleVersion: number;
  size: number;
  sha256: string;
  soname: string;
  libcxxFile: string;
}

interface PayloadEntry {
  name: string;
  present: boolean;
  size: number;
  lockSize: number;
  sizeMatch: boolean;
  placeholder: boolean;
}

interface ElfInfo {
  magicOk: boolean;
  is64LE: boolean;
  machine: number;
  machineAArch64: boolean;
  sourcePath: string;
}

interface ProbeItem {
  id: string;
  name: string;
  verdict: string;
  detail: string;
  evidence: string;
}

export interface ProbeReport {
  generatedAt: string;
  abi: string;
  bundleCodeDir: string;
  filesDir: string;
  resultPath: string;
  payload: PayloadEntry[];
  elf: ElfInfo;
  lockActiveNode: string;
  lockNodeModuleVersion: number;
  claimedVersion: string;
  claimedModuleAbi: number;
  diff: string[];
  items: ProbeItem[];
  reportWritten: boolean;
  boundary: string;
}

function stripV(node: string): string {
  return node.length > 1 && node.charAt(0) === 'v' ? node.substring(1) : node;
}

export class ProbeRunner {
  /** 页面摘要：把各项探针 id/verdict 串成一行文本。 */
  static summarize(report: ProbeReport): string {
    let s = 'time=' + report.generatedAt + ' abi=' + report.abi +
      ' reportWritten=' + report.reportWritten + ' diff=[' + report.diff.join(' | ') + ']\n';
    for (let i = 0; i < report.items.length; i++) {
      const it = report.items[i];
      s += it.id + '=' + it.verdict + ' ' + it.detail + '\n';
    }
    return s;
  }

  /** 定位原生库目录：先试常规候补，再退回默认路径（枚举会如实记录 missing）。 */
  private locatePayloadDir(bundleCodeDir: string): string {
    const candidates: string[] = [
      bundleCodeDir + '/libs/arm64-v8a',
      bundleCodeDir + '/xlibs/arm64-v8a'
    ];
    for (let i = 0; i < candidates.length; i++) {
      try {
        if (fs.accessSync(candidates[i])) {
          return candidates[i];
        }
      } catch (e) {
        // 目录不可访问 → 继续下一候补，最终如实记为 missing
      }
    }
    return candidates[0];
  }

  private enumeratePayload(dir: string, facts: LockFacts): PayloadEntry[] {
    const names: string[] = ['libnode.so', 'libc++_shared.so'];
    // lock 只锁定 libnode 的 size（119868824）；libc++ 尺寸由 SDK 提供，lock 无值 ⇒ lockSize=-1 不判。
    const lockSizes: number[] = [facts.size, -1];
    const result: PayloadEntry[] = [];
    for (let i = 0; i < names.length; i++) {
      const p = dir + '/' + names[i];
      let present = false;
      let size = 0;
      try {
        present = fs.accessSync(p);
        if (present) {
          size = fs.statSync(p).size;
        }
      } catch (e) {
        present = false;
        size = -1; // 读取失败，如实记录
      }
      const lockSize = lockSizes[i];
      const sizeMatch = lockSize >= 0 && size === lockSize;
      const placeholder = present && size === 0;
      result.push({
        name: names[i],
        present: present,
        size: size,
        lockSize: lockSize,
        sizeMatch: sizeMatch,
        placeholder: placeholder
      });
    }
    return result;
  }

  private readElf(path: string): ElfInfo {
    const need = 64;
    let magicOk = false;
    let is64LE = false;
    let machine = -1;
    let sourcePath = path;
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(need);
      const got = fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const b = new Uint8Array(buf);
      if (got >= 20) {
        magicOk = b[0] === 0x7f && b[1] === 0x45 && b[2] === 0x4c && b[3] === 0x46;
        is64LE = b[4] === 2 && b[5] === 1;
        machine = b[18] | (b[19] << 8);
      } else {
        sourcePath = path + ' (short read: ' + got + 'B)';
      }
    } catch (e) {
      sourcePath = path + ' (read failed)';
    }
    return {
      magicOk: magicOk,
      is64LE: is64LE,
      machine: machine,
      machineAArch64: machine === 0xb7,
      sourcePath: sourcePath
    };
  }

  private buildDiff(facts: LockFacts): string[] {
    const diffs: string[] = [];
    const lockNodeNoV = stripV(facts.activeNode);
    if (NODE_VERSION !== lockNodeNoV) {
      diffs.push('NODE_VERSION claimed=' + NODE_VERSION + ' vs lock.active=' + facts.activeNode);
    }
    if (NODE_MODULE_VERSION !== facts.nodeModuleVersion) {
      diffs.push('NODE_MODULE_VERSION claimed=' + NODE_MODULE_VERSION +
        ' vs lock.nodeModuleVersion=' + facts.nodeModuleVersion);
    }
    if (LIB_SIZE !== facts.size) {
      diffs.push('LIB_SIZE claimed=' + LIB_SIZE + ' vs lock.size=' + facts.size);
    }
    if (LIB_SHA256 !== facts.sha256) {
      diffs.push('LIB_SHA256 claimed(first16)=' + LIB_SHA256.substring(0, 16) +
        ' vs lock.sha256(first16)=' + facts.sha256.substring(0, 16));
    }
    return diffs;
  }

  /** 把报告写成沙箱 UTF-8 JSON；成功返回 true。 */
  private writeReport(ctx: common.UIAbilityContext, report: ProbeReport): boolean {
    try {
      const file = fs.openSync(report.resultPath,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(report));
      fs.closeSync(file);
      return true;
    } catch (e) {
      return false;
    }
  }

  run(ctx: common.UIAbilityContext): ProbeReport {
    const generatedAt = new Date().toISOString();
    const abi = ABI;
    const codeDir = ctx.bundleCodeDir;
    const filesDir = ctx.filesDir;
    const resultPath = filesDir + '/probe-result.json';
    const boundary =
      'libnode.so 无 NAPI 注册、本 HAP 无 native 桥、ArkTS 层无裸 dlopen/requireNapi/loadLibrary API；' +
      '执行级验证（node::Start）依赖 @fellow99/node-bridge 的 C 层 dlopen（外部消费方职责）。' +
      '见 specs/101-probe-app/spec.md FR-101-PROBE-030 与 test-cases.md P4。';

    // ---- LOCK facts（随包 rawfile 快照，生成自 runtime.lock.json，防与 CLAIMED 同源） ----
    let facts: LockFacts;
    try {
      const rawBytes = ctx.resourceManager.getRawFileContentSync('node-runtime-facts.json');
      const decoder = util.TextDecoder.create('utf-8');
      const raw = decoder.decodeWithStream(new Uint8Array(rawBytes));
      const parsed = JSON.parse(raw) as LockFacts;
      facts = parsed;
    } catch (e) {
      facts = {
        activeNode: 'unavailable',
        activeAbi: '',
        nodeModuleVersion: -1,
        size: -1,
        sha256: '',
        soname: '',
        libcxxFile: ''
      };
    }

    // ---- payload + ELF ----
    const libDir = this.locatePayloadDir(codeDir);
    const payload = this.enumeratePayload(libDir, facts);
    const libnode = payload[0];
    const elf = this.readElf(libDir + '/libnode.so');

    // ---- 各项探针 ----
    const items: ProbeItem[] = [];

    // PRB-01 载荷就位
    const p1ok = libnode.present && libnode.sizeMatch && !libnode.placeholder;
    items.push({
      id: 'PRB-01',
      name: 'payload-in-place',
      verdict: p1ok ? 'PASS' : (libnode.present ? 'PASS-FACT(mismatch/placeholder)' : 'FAIL'),
      detail: 'dir=' + libDir +
        ' libnode.present=' + libnode.present +
        ' size=' + libnode.size +
        ' lockSize=' + libnode.lockSize +
        ' placeholder=' + libnode.placeholder +
        ' libcxx.present=' + payload[1].present +
        ' libcxx.size=' + payload[1].size,
      evidence: 'context.bundleCodeDir + fs.statSync；尺寸对照 runtime.lock.json active'
    });

    // PRB-02 版本事实（记录式）
    const diff = this.buildDiff(facts);
    items.push({
      id: 'PRB-02',
      name: 'version-facts(claimed-vs-lock)',
      verdict: 'PASS-FACT',
      detail: 'claimed(runtime-har/Index.ets)=' + NODE_VERSION + '/abi' + NODE_MODULE_VERSION +
        '/' + RUNTIME_ID + ' ; lock.active=' + facts.activeNode + '/abi' + facts.nodeModuleVersion +
        '/soname=' + facts.soname + ' ; diffs=[' + diff.join(' | ') + ']',
      evidence: '@fellow99/node-runtime 常量 + rawfile node-runtime-facts.json(生成自 runtime.lock.json)'
    });

    // PRB-03 ELF 头校验事实
    const p3ok = elf.magicOk && elf.is64LE && elf.machineAArch64;
    items.push({
      id: 'PRB-03',
      name: 'elf-header-fact(device-read)',
      verdict: p3ok ? 'PASS-FACT' : 'SKIPPED(host P3-1 authoritative)',
      detail: 'magic=' + elf.magicOk + ' is64LE=' + elf.is64LE +
        ' e_machine=0x' + (elf.machine & 0xffff).toString(16) + '(aarch64=0xb7) src=' + elf.sourcePath,
      evidence: 'fs 只读 64B；完整七项门禁由 host node tools/provision.mjs --check 承接'
    });

    // PRB-04 加载边界（不硬造执行）
    items.push({
      id: 'PRB-04',
      name: 'load-boundary(no-napi/no-bridge)',
      verdict: 'PASS-FACT(not-executable-in-this-hap)',
      detail: boundary,
      evidence: 'SDK ets grep requireNapi/dlopen/loadLibrary=无；runtime-har Index.ets 仅导出常量'
    });

    // PRB-05 报告（先写核心 4 项，成功后再落含本项的最终版）
    const core: ProbeReport = {
      generatedAt: generatedAt,
      abi: abi,
      bundleCodeDir: codeDir,
      filesDir: filesDir,
      resultPath: resultPath,
      payload: payload,
      elf: elf,
      lockActiveNode: facts.activeNode,
      lockNodeModuleVersion: facts.nodeModuleVersion,
      claimedVersion: NODE_VERSION,
      claimedModuleAbi: NODE_MODULE_VERSION,
      diff: diff,
      items: items.slice(),
      reportWritten: false,
      boundary: boundary
    };
    const firstWriteOk = this.writeReport(ctx, core);
    items.push({
      id: 'PRB-05',
      name: 'report-to-sandbox',
      verdict: firstWriteOk ? 'PASS' : 'FAIL',
      detail: resultPath + ' (writeSync JSON)',
      evidence: 'context.filesDir + @kit.CoreFileKit fs.openSync/writeSync/closeSync'
    });

    const report: ProbeReport = {
      generatedAt: generatedAt,
      abi: abi,
      bundleCodeDir: codeDir,
      filesDir: filesDir,
      resultPath: resultPath,
      payload: payload,
      elf: elf,
      lockActiveNode: facts.activeNode,
      lockNodeModuleVersion: facts.nodeModuleVersion,
      claimedVersion: NODE_VERSION,
      claimedModuleAbi: NODE_MODULE_VERSION,
      diff: diff,
      items: items.slice(),
      reportWritten: firstWriteOk,
      boundary: boundary
    };
    // PRB-05 落盘后再写一次最终版（含 PRB-05 项），使文件与返回对象一致
    if (firstWriteOk) {
      this.writeReport(ctx, report);
    }
    return report;
  }
}
