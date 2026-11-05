import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0xD101;
const TAG = 'NODE_RUNTIME_PROBE';

/**
 * probe-app EntryAbility。
 *
 * 无头模式：
 *   hdc shell "aa start -a EntryAbility -b org.fellow99.noderuntime.probe --ps probeAuto true"
 *   — `probeAuto=true` ⇒ 页面出现后自动执行全部探针（PRB-01..05），结果写沙箱。
 *   — `aa start --ps` 每次只送得动一个 token（多词 flags 会被截断），本探针只消费单值键。
 *   — 缺省（没有 probeAuto）⇒ 等人工点「运行探针」，不自动执行。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    let auto: string = '';
    const params: Record<string, Object> | undefined = want.parameters;
    if (params !== undefined) {
      const raw: Object | undefined = params['probeAuto'];
      if (raw !== undefined) {
        auto = raw as string;
      }
    }
    AppStorage.setOrCreate<string>('probeAuto', auto);
    hilog.info(DOMAIN, TAG, 'onCreate probeAuto=%{public}s bundleCodeDir=%{public}s filesDir=%{public}s',
      auto, this.context.bundleCodeDir, this.context.filesDir);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent ok');
    });
  }
}
