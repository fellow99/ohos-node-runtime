import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProbeRunner } from '../common/probe-runner';

const DOMAIN = 0xD101;
const TAG = 'NODE_RUNTIME_PROBE_PAGE';

/**
 * probe-app 结果摘要页。
 * - 无头：aboutToAppear 读 AppStorage['probeAuto']==='true' ⇒ 自动跑一次；
 * - 手动：点「运行探针」。
 * 详细 JSON 在设备侧写 filesDir/probe-result.json（hdc file recv 拉取）。
 */
@Entry
@Component
struct Index {
  @State summary: string = '未运行（点按钮，或 aa start --ps probeAuto true 自动跑）';
  @State running: boolean = false;
  private runner: ProbeRunner = new ProbeRunner();

  private doProbe(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    this.summary = '运行中…';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const report = this.runner.run(ctx);
      this.summary = ProbeRunner.summarize(report);
      hilog.info(DOMAIN, TAG, 'probe done, reportWritten=%{public}s',
        report.reportWritten ? 'true' : 'false');
    } catch (e) {
      this.summary = '探针异常: ' + JSON.stringify(e);
    }
    this.running = false;
  }

  aboutToAppear(): void {
    const v = AppStorage.get<string>('probeAuto');
    const auto: string = v === undefined ? '' : v;
    if (auto === 'true') {
      this.doProbe();
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('Node Runtime Probe (101-probe-app)')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      Scroll() {
        Text(this.summary)
          .fontSize(13)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('95%')
      .height(320)
      .border({ width: 1, color: '#DDDDDD' })
      Button('运行探针 (PRB-01..05)')
        .onClick(() => this.doProbe())
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .justifyContent(FlexAlign.Center)
  }
}
