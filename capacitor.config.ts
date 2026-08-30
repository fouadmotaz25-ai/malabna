import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "iq.nextmove.app",
  appName: "NextMove",
  webDir: "mobile-dist",
  backgroundColor: "#0b1220",
  server: {
    androidScheme: "https",
    iosScheme: "https",
  },
  android: {
    backgroundColor: "#0b1220",
    allowMixedContent: false,
  },
  ios: {
    backgroundColor: "#0b1220",
    contentInset: "automatic",
  },
};

export default config;
