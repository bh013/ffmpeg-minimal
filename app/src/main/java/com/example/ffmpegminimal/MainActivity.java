package com.example.ffmpegminimal;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.BufferedReader;
import java.io.InputStreamReader;

public class MainActivity extends Activity {
    
    private TextView logView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        logView = findViewById(R.id.logView);
        
        new Thread(() -> {
            try {
                File ffmpegFile = new File(getFilesDir(), "ffmpeg");
                if (!ffmpegFile.exists() || ffmpegFile.length() == 0) {
                    log("Extracting FFmpeg binary to internal storage...");
                    InputStream is = getAssets().open("armeabi-v7a/ffmpeg");
                    FileOutputStream os = new FileOutputStream(ffmpegFile);
                    byte[] buffer = new byte[8192];
                    int read;
                    while ((read = is.read(buffer)) != -1) {
                        os.write(buffer, 0, read);
                    }
                    os.flush();
                    os.close();
                    is.close();
                    ffmpegFile.setExecutable(true);
                    log("Extraction complete.");
                } else {
                    log("FFmpeg binary already exists.");
                    ffmpegFile.setExecutable(true);
                }
                
                log("\n--- Testing FFmpeg ---");
                log("Executing: " + ffmpegFile.getAbsolutePath() + " -version");
                
                ProcessBuilder pb = new ProcessBuilder(ffmpegFile.getAbsolutePath(), "-version");
                pb.redirectErrorStream(true);
                Process process = pb.start();
                
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    log(line);
                }
                
                int exitCode = process.waitFor();
                log("\n--- Process finished with exit code " + exitCode + " ---");
            } catch (Exception e) {
                log("Error: " + e.getMessage());
            }
        }).start();
    }
    
    private void log(final String text) {
        runOnUiThread(() -> logView.append(text + "\n"));
    }
}