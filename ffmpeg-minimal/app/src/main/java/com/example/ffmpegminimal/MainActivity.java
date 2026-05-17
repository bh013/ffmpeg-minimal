package com.example.ffmpegminimal;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;

public class MainActivity extends Activity {

    private TextView tvOutput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        tvOutput = findViewById(R.id.tvOutput);
        
        new Thread(() -> {
            try {
                File ffmpegFile = new File(getFilesDir(), "ffmpeg");
                if (!ffmpegFile.exists()) {
                    InputStream is = getAssets().open("armeabi-v7a/ffmpeg");
                    OutputStream os = new FileOutputStream(ffmpegFile);
                    byte[] buffer = new byte[4096];
                    int read;
                    while ((read = is.read(buffer)) != -1) {
                        os.write(buffer, 0, read);
                    }
                    os.flush();
                    os.close();
                    is.close();
                }
                
                ffmpegFile.setExecutable(true);
                
                Process process = Runtime.getRuntime().exec(new String[]{ffmpegFile.getAbsolutePath(), "-version"});
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                StringBuilder output = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
                process.waitFor();
                
                runOnUiThread(() -> tvOutput.setText("FFmpeg Ready:\n" + output.toString()));
                
            } catch (Exception e) {
                runOnUiThread(() -> tvOutput.setText("Error: " + e.getMessage()));
            }
        }).start();
    }
}