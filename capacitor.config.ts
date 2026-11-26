import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
    // Same id as the Play listing of the earlier app, so this ships as an update.
    appId: 'com.yusufdinc.linguareader',
    appName: 'LinguaReader',
    webDir: 'dist',
    android: {
        allowMixedContent: false,
    },
};

export default config;
