import registerAudioTools from "./audio";
import registerScreenshotTools from "./screenshot";
import registerScreenTools from "./screen";

export default function (api: any) {
  registerAudioTools(api);
  registerScreenshotTools(api);
  registerScreenTools(api);
}
