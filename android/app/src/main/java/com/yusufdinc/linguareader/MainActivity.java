package com.yusufdinc.linguareader;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // The app's own native code (offline dictionaries, text recognition models)
        registerPlugin(DictionaryPlugin.class);
        registerPlugin(OcrPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
